//
//  FileSystemService.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation
import Combine

/// 文件系统服务
/// 负责文件系统扫描、权限管理和数据访问
@Observable
class FileSystemService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前扫描状态
    @Published var scanningState: ScanningState = .idle
    
    /// 扫描进度（0.0 - 1.0）
    @Published var scanProgress: Double = 0.0
    
    /// 当前正在扫描的路径
    @Published var currentScanPath: String = ""
    
    /// 扫描错误信息
    @Published var errorMessage: String?
    
    /// 可用的卷列表
    @Published var availableVolumes: [VolumeInfo] = []
    
    // MARK: - Private Properties
    
    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        loadAvailableVolumes()
    }
    
    deinit {
        cancelCurrentScan()
    }
    
    // MARK: - Volume Management
    
    /// 加载可用卷列表
    private func loadAvailableVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey
        ]
        
        guard let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) else {
            return
        }
        
        availableVolumes = urls.compactMap { url in
            VolumeInfo.from(url: url)
        }.sorted { $0.name < $1.name }
    }
    
    /// 刷新卷列表
    func refreshVolumes() {
        loadAvailableVolumes()
    }
    
    // MARK: - Scanning Operations
    
    /// 扫描指定目录
    /// - Parameter url: 要扫描的目录 URL
    /// - Returns: 扫描结果的树节点
    func scanDirectory(at url: URL) async throws -> TreeNode {
        // 检查权限
        guard await checkAccessPermission(for: url) else {
            throw FileSystemError.accessDenied(url.path)
        }
        
        // 更新状态
        await MainActor.run {
            scanningState = .scanning
            scanProgress = 0.0
            currentScanPath = url.path
            errorMessage = nil
        }
        
        do {
            let rootItem = try await scanDirectoryRecursively(url: url, depth: 0)
            let treeNode = TreeNode.build(from: rootItem)
            
            await MainActor.run {
                scanningState = .completed
                scanProgress = 1.0
                currentScanPath = ""
            }
            
            return treeNode
        } catch {
            await MainActor.run {
                scanningState = .error
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// 递归扫描目录
    /// - Parameters:
    ///   - url: 目录 URL
    ///   - depth: 当前深度
    ///   - maxDepth: 最大深度限制
    /// - Returns: 文件系统项目
    private func scanDirectoryRecursively(
        url: URL,
        depth: Int,
        maxDepth: Int = 20
    ) async throws -> FileSystemItem {
        
        // 检查是否需要取消
        try Task.checkCancellation()
        
        // 深度限制
        guard depth < maxDepth else {
            throw FileSystemError.maxDepthExceeded
        }
        
        // 更新当前扫描路径
        await MainActor.run {
            currentScanPath = url.path
        }
        
        // 创建文件系统项目
        guard let item = FileSystemItem.from(url: url) else {
            throw FileSystemError.invalidPath(url.path)
        }
        
        // 如果是目录，扫描子项目
        if item.isDirectory {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [
                        .nameKey,
                        .fileSizeKey,
                        .isDirectoryKey,
                        .contentTypeKey,
                        .creationDateKey,
                        .contentModificationDateKey
                    ],
                    options: [.skipsHiddenFiles]
                )
                
                var processedCount = 0
                for childURL in contents {
                    // 检查是否需要取消
                    try Task.checkCancellation()
                    
                    do {
                        let childItem = try await scanDirectoryRecursively(
                            url: childURL,
                            depth: depth + 1,
                            maxDepth: maxDepth
                        )
                        item.addChild(childItem)
                    } catch {
                        // 记录错误但继续扫描其他文件
                        print("Error scanning \(childURL.path): \(error)")
                    }
                    
                    processedCount += 1
                    
                    // 更新进度（简化的进度计算）
                    if depth == 0 {
                        let progress = Double(processedCount) / Double(contents.count)
                        await MainActor.run {
                            scanProgress = min(progress, 0.95) // 保留5%给最终处理
                        }
                    }
                }
            } catch {
                // 如果无法访问目录，记录错误但不抛出异常
                print("Cannot access directory \(url.path): \(error)")
            }
        }
        
        return item
    }
    
    /// 取消当前扫描
    func cancelCurrentScan() {
        scanTask?.cancel()
        scanTask = nil
        
        scanningState = .cancelled
        scanProgress = 0.0
        currentScanPath = ""
    }
    
    // MARK: - Permission Management
    
    /// 检查目录访问权限
    /// - Parameter url: 目录 URL
    /// - Returns: 是否有访问权限
    func checkAccessPermission(for url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            // 检查基本文件系统权限
            guard fileManager.isReadableFile(atPath: url.path) else {
                continuation.resume(returning: false)
                return
            }
            
            // 尝试读取目录内容以确认权限
            do {
                _ = try fileManager.contentsOfDirectory(atPath: url.path)
                continuation.resume(returning: true)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    /// 请求完全磁盘访问权限
    /// - Returns: 是否成功获取权限
    @MainActor
    func requestFullDiskAccess() -> Bool {
        // 在实际应用中，这里会显示权限请求对话框
        // 现在只是检查当前权限状态
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let testURL = homeDirectory.appendingPathComponent("Desktop")
        
        return fileManager.isReadableFile(atPath: testURL.path)
    }
    
    // MARK: - File Operations
    
    /// 获取文件或目录的详细信息
    /// - Parameter url: 文件或目录 URL
    /// - Returns: 详细信息字典
    func getDetailedInfo(for url: URL) async throws -> [String: Any] {
        let resourceKeys: [URLResourceKey] = [
            .nameKey,
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey,
            .contentTypeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .fileResourceTypeKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ]
        
        let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
        
        var info: [String: Any] = [:]
        
        info["name"] = resourceValues.name
        info["path"] = url.path
        info["size"] = resourceValues.fileSize ?? 0
        info["totalSize"] = resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0
        info["isDirectory"] = resourceValues.isDirectory ?? false
        info["contentType"] = resourceValues.contentType?.description
        info["creationDate"] = resourceValues.creationDate
        info["modificationDate"] = resourceValues.contentModificationDate
        info["accessDate"] = resourceValues.contentAccessDate
        info["isHidden"] = resourceValues.isHidden ?? false
        info["isPackage"] = resourceValues.isPackage ?? false
        info["isSymbolicLink"] = resourceValues.isSymbolicLink ?? false
        
        return info
    }
    
    /// 计算目录大小
    /// - Parameter url: 目录 URL
    /// - Returns: 目录总大小（字节）
    func calculateDirectorySize(at url: URL) async throws -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FileSystemError.invalidPath(url.path)
        }
        
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            
            if resourceValues.isDirectory != true {
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        }
        
        return totalSize
    }
}

// MARK: - Supporting Types

/// 扫描状态枚举
enum ScanningState {
    case idle
    case scanning
    case completed
    case cancelled
    case error
    
    var description: String {
        switch self {
        case .idle: return "就绪"
        case .scanning: return "扫描中"
        case .completed: return "完成"
        case .cancelled: return "已取消"
        case .error: return "错误"
        }
    }
}
