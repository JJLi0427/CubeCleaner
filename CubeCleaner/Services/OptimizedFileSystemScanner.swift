//
//  OptimizedFileSystemScanner.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2025-08-07.
//

import Foundation
import CoreServices

// Protocol for optimized scanning using system indices
protocol OptimizedFileSystemScannerProtocol {
    func scanWithSpotlight(url: URL, excludedPaths: [String], depth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> ScanResult
    func scanWithFileSystemEvents(url: URL, excludedPaths: [String], depth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> ScanResult
    func quickSizeCalculation(url: URL) async throws -> Int64
    func cancelScan()
    var progress: Progress { get }
}

// Optimized scanner implementation using system indices and APIs
class OptimizedFileSystemScanner: OptimizedFileSystemScannerProtocol {
    private let fileManager = FileManager.default
    private var isCancelled = false
    private(set) var progress = Progress(totalUnitCount: 1)
    private var spotlightQuery: NSMetadataQuery?
    
    // MARK: - Public Methods
    
    /// Uses Spotlight index for fast scanning
    func scanWithSpotlight(url: URL, excludedPaths: [String] = [], depth: Int? = nil, excludeSystemFiles: Bool = true, excludeHiddenFiles: Bool = true) async throws -> ScanResult {
        // Reset state
        isCancelled = false
        progress = Progress(totalUnitCount: 1)
        progress.localizedDescription = "使用 Spotlight 索引扫描: \(url.path)"
        
        // Check if the URL exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.fileNotFound(url)
        }
        
        let rootItem = try await scanWithSpotlightIndex(url: url, excludedPaths: excludedPaths, depth: depth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
        
        return ScanResult(
            rootItem: rootItem,
            scanPath: url,
            excludedPaths: excludedPaths,
            scanDepth: depth,
            excludedSystemFiles: excludeSystemFiles,
            excludedHiddenFiles: excludeHiddenFiles
        )
    }

    /// Scans using File System Events (FSEvents) - Not yet implemented, falls back to regular scanning.
    /// This is a placeholder and does NOT use FSEvents yet.
    func scanWithFileSystemEvents(url: URL, excludedPaths: [String] = [], depth: Int? = nil, excludeSystemFiles: Bool = true, excludeHiddenFiles: Bool = true) async throws -> ScanResult {
        // Reset state
        isCancelled = false
        progress = Progress(totalUnitCount: 1)
        progress.localizedDescription = "使用文件系统事件扫描（尚未实现，使用常规扫描）: \(url.path)"

        // Check if the URL exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.fileNotFound(url)
        }

        // FSEvents integration not implemented; fallback to optimized directory scan
        let rootItem = try await scanDirectoryOptimized(url, excludedPaths: excludedPaths, currentDepth: 0, maxDepth: depth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)

        return ScanResult(
            rootItem: rootItem,
            scanPath: url,
            excludedPaths: excludedPaths,
            scanDepth: depth,
            excludedSystemFiles: excludeSystemFiles,
            excludedHiddenFiles: excludeHiddenFiles
        )
    }
    
    /// Quick size calculation using system APIs
    func quickSizeCalculation(url: URL) async throws -> Int64 {
        progress.localizedDescription = "快速计算大小: \(url.path)"
        
        // Use URLResourceValues for optimized size calculation
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let size = try await calculateSizeUsingResourceValues(url: url)
                    continuation.resume(returning: size)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func cancelScan() {
        isCancelled = true
        spotlightQuery?.stop()
    }
    
    // MARK: - Private Methods - Spotlight Integration
    
    private func scanWithSpotlightIndex(url: URL, excludedPaths: [String], depth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> FileSystemItem {
        // Create metadata query for Spotlight
        let query = NSMetadataQuery()
        spotlightQuery = query
        
        // Set search scope to the specific directory
        query.searchScopes = [url]
        
        // Build predicate for file search
        var predicateFormat = "TRUEPREDICATE"
        
        if excludeHiddenFiles {
            predicateFormat += " AND NOT (kMDItemFSName BEGINSWITH '.')"
        }
        
        if excludeSystemFiles {
            predicateFormat += " AND NOT (kMDItemFSName LIKE 'System*' OR kMDItemFSName LIKE 'Library*')"
        }
        
        query.predicate = NSPredicate(format: predicateFormat)
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            // Set up notification observers
            let notificationCenter = NotificationCenter.default
            var observers: [NSObjectProtocol] = []
            
            let finishedObserver = notificationCenter.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                guard !hasResumed else { return }
                hasResumed = true
                
                Task {
                    do {
                        let rootItem = try await self.buildFileSystemItemFromSpotlightResults(query: query, rootURL: url, excludedPaths: excludedPaths, depth: depth)
                        continuation.resume(returning: rootItem)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                
                // Clean up observers
                observers.forEach { notificationCenter.removeObserver($0) }
            }
            
            let updateObserver = notificationCenter.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { _ in
                self.progress.localizedDescription = "Spotlight 索引搜索中... (\(query.resultCount) 项)"
            }
            
            observers = [finishedObserver, updateObserver]
            
            // Start the query
            if !query.start() {
                hasResumed = true
                observers.forEach { notificationCenter.removeObserver($0) }
                continuation.resume(throwing: ScannerError.unknown(NSError(domain: "SpotlightError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法启动 Spotlight 查询"])))
            }
        }
    }
    
    private func buildFileSystemItemFromSpotlightResults(query: NSMetadataQuery, rootURL: URL, excludedPaths: [String], depth: Int?) async throws -> FileSystemItem {
        // Stop the query
        query.stop()
        
        // Build directory structure from Spotlight results
        var directoryStructure: [String: [FileSystemItem]] = [:]
        
        for i in 0..<query.resultCount {
            if isCancelled {
                throw ScannerError.cancelled
            }
            
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            
            let itemURL = URL(fileURLWithPath: path)
            
            // Check exclusions
            if excludedPaths.contains(where: { path.hasPrefix($0) }) {
                continue
            }
            
            // Check depth if specified
            if let maxDepth = depth {
                let relativePath = String(path.dropFirst(rootURL.path.count))
                let currentDepth = relativePath.components(separatedBy: "/").count - 1
                if currentDepth > maxDepth {
                    continue
                }
            }
            
            do {
                let fileItem = try FileSystemItem(url: itemURL)
                let parentPath = itemURL.deletingLastPathComponent().path
                
                if directoryStructure[parentPath] == nil {
                    directoryStructure[parentPath] = []
                }
                directoryStructure[parentPath]?.append(fileItem)
            } catch {
                // Skip items we can't process
                continue
            }
        }
        
        // Build the root item with organized children
        return try await buildDirectoryHierarchy(rootURL: rootURL, directoryStructure: directoryStructure)
    }
    
    private func buildDirectoryHierarchy(rootURL: URL, directoryStructure: [String: [FileSystemItem]]) async throws -> FileSystemItem {
        // Recursively build directory structure
        func buildItem(for url: URL) throws -> FileSystemItem {
            let childrenItems = directoryStructure[url.path]?.compactMap { item in
                if item.isDirectory {
                    // Recursively build children for directories
                    return try? buildItem(for: item.url)
                } else {
                    return item
                }
            }
            return try FileSystemItem(url: url, children: (childrenItems?.isEmpty ?? true) ? nil : childrenItems)
        }
        return try buildItem(for: rootURL)
    }
    
    // MARK: - Private Methods - Optimized Scanning
    
    private func scanDirectoryOptimized(_ url: URL, excludedPaths: [String], currentDepth: Int, maxDepth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> FileSystemItem {
        // Check if cancelled
        if isCancelled {
            throw ScannerError.cancelled
        }
        
        // Update progress
        progress.localizedDescription = url.path
        
        // Check if we've reached the maximum depth
        let shouldScanChildren = maxDepth == nil || currentDepth < maxDepth!
        
        var children: [FileSystemItem]? = nil
        
        if shouldScanChildren {
            // Use optimized directory enumeration
            children = try await enumerateDirectoryOptimized(url: url, excludedPaths: excludedPaths, currentDepth: currentDepth, maxDepth: maxDepth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
        }
        // Check if we've reached the maximum depth
        let shouldScanChildren: Bool
        if let maxDepth = maxDepth {
            shouldScanChildren = currentDepth < maxDepth
        } else {
            shouldScanChildren = true
        }
        
        var children: [FileSystemItem]? = nil
    private func enumerateDirectoryOptimized(url: URL, excludedPaths: [String], currentDepth: Int, maxDepth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> [FileSystemItem]? {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isSystemImmutableKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { (url, error) in
                // Log error but continue enumeration
                print("警告: 无法访问 \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            return nil
        }
        
        var items: [FileSystemItem] = []
        
        for case let itemURL as URL in enumerator {
            if isCancelled {
                throw ScannerError.cancelled
            }
            
            // Check exclusions
            if excludedPaths.contains(where: { itemURL.path.hasPrefix($0) }) {
                continue
            }
            
            do {
                let resourceValues = try itemURL.resourceValues(forKeys: resourceKeys)
                
                // Apply filters
                if excludeHiddenFiles && (resourceValues.isHidden ?? false) {
                    continue
                }
                
                if excludeSystemFiles && (resourceValues.isSystemImmutable ?? false) {
                    continue
                }
                
                // Create item
                if resourceValues.isDirectory ?? false {
                    let childItem = try await scanDirectoryOptimized(itemURL, excludedPaths: excludedPaths, currentDepth: currentDepth + 1, maxDepth: maxDepth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
                    items.append(childItem)
                } else {
                    let fileItem = try FileSystemItem(url: itemURL)
                    items.append(fileItem)
                }
                
                progress.completedUnitCount += 1
            } catch {
                // Skip items we can't access
                continue
            }
        }
        
        return items.isEmpty ? nil : items
    }
    
    // MARK: - Private Methods - Size Calculation
    
    private func calculateSizeUsingResourceValues(url: URL) async throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .totalFileSizeKey, .fileAllocatedSizeKey]
        
        // Try to get total size directly for directories
        do {
            let resourceValues = try url.resourceValues(forKeys: resourceKeys)
            
            if let isDirectory = resourceValues.isDirectory, isDirectory {
                // For directories, try to get total file size first
                if let totalSize = resourceValues.totalFileSize {
                    return Int64(totalSize)
                }
                
                // Fall back to enumeration
                return try await enumerateForSize(url: url)
            } else {
                // For files, return the file size
                return Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            throw ScannerError.accessDenied(url)
        }
    }
    
    private func enumerateForSize(url: URL) async throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .fileAllocatedSizeKey]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            throw ScannerError.accessDenied(url)
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if isCancelled {
                throw ScannerError.cancelled
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                if let fileSize = resourceValues.fileSize, !(resourceValues.isDirectory ?? false) {
                    totalSize += Int64(fileSize)
                }
            } catch {
                // Skip files we can't access
                continue
            }
        }
        
        return totalSize
    }
}

// MARK: - Extensions

extension OptimizedFileSystemScanner {
    /// Batch operation for scanning multiple directories
    func batchScan(urls: [URL], excludedPaths: [String] = [], depth: Int? = nil, excludeSystemFiles: Bool = true, excludeHiddenFiles: Bool = true) async throws -> [ScanResult] {
        var results: [ScanResult] = []
        
        for url in urls {
            if isCancelled {
                throw ScannerError.cancelled
            }
            
            do {
                let result = try await scanWithSpotlight(url: url, excludedPaths: excludedPaths, depth: depth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
                results.append(result)
            } catch {
                // Continue with other URLs even if one fails
                print("警告: 扫描 \(url.path) 失败: \(error.localizedDescription)")
                continue
            }
        }
        
        return results
    }
    
    /// Get file system statistics
    func getFileSystemStats(for url: URL) async throws -> FileSystemStats {
        progress.localizedDescription = "收集文件系统统计信息: \(url.path)"
        
        let resourceKeys: Set<URLResourceKey> = [
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        
        let resourceValues = try url.resourceValues(forKeys: resourceKeys)
        
        return FileSystemStats(
            totalCapacity: Int64(resourceValues.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(resourceValues.volumeAvailableCapacity ?? 0),
            availableCapacityForImportantUsage: Int64(resourceValues.volumeAvailableCapacityForImportantUsage ?? 0)
        )
    }
}

// MARK: - Supporting Types

struct FileSystemStats {
    let totalCapacity: Int64
    let availableCapacity: Int64
    let availableCapacityForImportantUsage: Int64
    
    var usedCapacity: Int64 {
        return totalCapacity - availableCapacity
    }
    
    var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0.0 }
        return Double(usedCapacity) / Double(totalCapacity) * 100.0
    }
}
