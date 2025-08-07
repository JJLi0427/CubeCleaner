//
//  FileSystemScanner.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation

// Protocol defining the scanner interface
protocol FileSystemScannerProtocol {
    func scan(url: URL, excludedPaths: [String], depth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> ScanResult
    func cancelScan()
    var progress: Progress { get }
}

// Errors that can occur during scanning
enum ScannerError: Error {
    case cancelled
    case accessDenied(URL)
    case fileNotFound(URL)
    case unknown(Error)
    
    var localizedDescription: String {
        switch self {
        case .cancelled:
            return "Scan was cancelled"
        case .accessDenied(let url):
            return "Access denied to \(url.path)"
        case .fileNotFound(let url):
            return "File not found at \(url.path)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// Main scanner implementation
class FileSystemScanner: FileSystemScannerProtocol {
    private let fileManager = FileManager.default
    private var isCancelled = false
    private(set) var progress = Progress(totalUnitCount: 1)
    
    // MARK: - Public Methods
    
    func scan(url: URL, excludedPaths: [String] = [], depth: Int? = nil, excludeSystemFiles: Bool = true, excludeHiddenFiles: Bool = true) async throws -> ScanResult {
        // Reset state
        isCancelled = false
        progress = Progress(totalUnitCount: 1)
        progress.localizedDescription = url.path
        
        // Check if the URL exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.fileNotFound(url)
        }
        
        // Start scanning
        do {
            let rootItem = try await scanDirectory(url, excludedPaths: excludedPaths, currentDepth: 0, maxDepth: depth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
            
            // Create and return the scan result
            return ScanResult(
                rootItem: rootItem,
                scanPath: url,
                excludedPaths: excludedPaths,
                scanDepth: depth,
                excludedSystemFiles: excludeSystemFiles,
                excludedHiddenFiles: excludeHiddenFiles
            )
        } catch let error as ScannerError {
            throw error
        } catch {
            throw ScannerError.unknown(error)
        }
    }
    
    func cancelScan() {
        isCancelled = true
    }
    
    // MARK: - Private Methods
    
    private func scanDirectory(_ url: URL, excludedPaths: [String], currentDepth: Int, maxDepth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> FileSystemItem {
        // Check if cancelled
        if isCancelled {
            throw ScannerError.cancelled
        }
        
        // Update progress
        progress.localizedDescription = url.path
        
        // Check if we've reached the maximum depth
        let shouldScanChildren = maxDepth == nil || currentDepth < maxDepth!
        
        // Get directory contents
        var children: [FileSystemItem]? = nil
        
        if shouldScanChildren {
            do {
                // Get contents of directory
                let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                
                // Filter contents based on exclusion criteria
                let filteredContents = contents.filter { itemURL in
                    // Check if path is in excluded paths
                    if excludedPaths.contains(where: { itemURL.path.hasPrefix($0) }) {
                        return false
                    }
                    
                    // Get file attributes to check for hidden and system files
                    do {
                        let resourceValues = try itemURL.resourceValues(forKeys: [.isHiddenKey, .isSystemImmutableKey])
                        
                        // Check if it's a hidden file and we're excluding those
                        if excludeHiddenFiles && (resourceValues.isHidden ?? false) {
                            return false
                        }
                        
                        // Check if it's a system file and we're excluding those
                        if excludeSystemFiles && (resourceValues.isSystemImmutable ?? false) {
                            return false
                        }
                        
                        return true
                    } catch {
                        // If we can't get attributes, include the file by default
                        return true
                    }
                }
                
                // Update progress total
                progress.totalUnitCount = Int64(filteredContents.count + 1)
                
                // Scan each child item
                var scannedChildren: [FileSystemItem] = []
                for childURL in filteredContents {
                    do {
                        let childItem = try await scanItem(childURL, excludedPaths: excludedPaths, currentDepth: currentDepth + 1, maxDepth: maxDepth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
                        scannedChildren.append(childItem)
                        progress.completedUnitCount += 1
                    } catch {
                        // Skip items we can't access
                        continue
                    }
                }
                
                children = scannedChildren
            } catch {
                // If we can't access directory contents, create item without children
                children = nil
            }
        }
        
        // Create and return the FileSystemItem for this directory
        return try FileSystemItem(url: url, children: children)
    }
    
    private func scanItem(_ url: URL, excludedPaths: [String], currentDepth: Int, maxDepth: Int?, excludeSystemFiles: Bool, excludeHiddenFiles: Bool) async throws -> FileSystemItem {
        // Check if cancelled
        if isCancelled {
            throw ScannerError.cancelled
        }
        
        // Update progress
        progress.localizedDescription = url.path
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ScannerError.fileNotFound(url)
        }
        
        if isDirectory.boolValue {
            // It's a directory, scan it recursively
            return try await scanDirectory(url, excludedPaths: excludedPaths, currentDepth: currentDepth, maxDepth: maxDepth, excludeSystemFiles: excludeSystemFiles, excludeHiddenFiles: excludeHiddenFiles)
        } else {
            // It's a file, create a FileSystemItem for it
            return try FileSystemItem(url: url)
        }
    }
}

// Extension for calculating directory sizes without scanning children
extension FileSystemScanner {
    func calculateDirectorySize(url: URL) async throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: nil
        ) else {
            throw ScannerError.accessDenied(url)
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            // Check if cancelled
            if isCancelled {
                throw ScannerError.cancelled
            }
            
            // Update progress
            progress.localizedDescription = fileURL.path
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                if let fileSize = resourceValues.fileSize, !resourceValues.isDirectory! {
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