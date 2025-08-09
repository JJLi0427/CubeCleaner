//
//  ScanViewModel.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation
import SwiftUI
import Combine

/// 扫描视图模型
/// 管理文件系统扫描流程、状态和用户交互
@Observable
class ScanViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前扫描的根节点
    @Published var rootNode: TreeNode?
    
    /// 选中的目录 URL
    @Published var selectedDirectoryURL: URL?
    
    /// 扫描状态
    @Published var scanningState: ScanningState = .idle
    
    /// 扫描进度 (0.0 - 1.0)
    @Published var scanProgress: Double = 0.0
    
    /// 当前扫描路径
    @Published var currentScanPath: String = ""
    
    /// 错误信息
    @Published var errorMessage: String?
    
    /// 是否显示错误警告
    @Published var showErrorAlert: Bool = false
    
    /// 是否显示权限请求对话框
    @Published var showPermissionAlert: Bool = false
    
    /// 扫描统计信息
    @Published var scanStatistics: ScanStatistics = ScanStatistics()
    
    /// 可用卷列表
    @Published var availableVolumes: [VolumeInfo] = []
    
    /// 选中的卷
    @Published var selectedVolume: VolumeInfo?
    
    // MARK: - Filter Properties
    
    /// 是否显示隐藏文件
    @Published var showHiddenFiles: Bool = false
    
    /// 文件大小过滤器
    @Published var fileSizeFilter: FileSizeFilter = .all
    
    /// 文件类型过滤器
    @Published var fileTypeFilters: Set<FileType> = Set(FileType.allCases)
    
    /// 最大扫描深度
    @Published var maxScanDepth: Int = 20
    
    // MARK: - Private Properties
    
    private let fileSystemService: FileSystemService
    private var scanTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(fileSystemService: FileSystemService = FileSystemService()) {
        self.fileSystemService = fileSystemService
        setupBindings()
        loadAvailableVolumes()
    }
    
    deinit {
        cancelScan()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // 监听文件系统服务状态变化
        fileSystemService.$scanningState
            .receive(on: DispatchQueue.main)
            .assign(to: &$scanningState)
        
        fileSystemService.$scanProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$scanProgress)
        
        fileSystemService.$currentScanPath
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentScanPath)
        
        fileSystemService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                self?.errorMessage = errorMessage
                self?.showErrorAlert = errorMessage != nil
            }
            .store(in: &cancellables)
        
        fileSystemService.$availableVolumes
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableVolumes)
    }
    
    // MARK: - Volume Management
    
    private func loadAvailableVolumes() {
        fileSystemService.refreshVolumes()
    }
    
    /// 选择卷进行扫描
    /// - Parameter volume: 要扫描的卷
    func selectVolume(_ volume: VolumeInfo) {
        selectedVolume = volume
        selectedDirectoryURL = volume.url
    }
    
    /// 选择自定义目录
    func selectCustomDirectory() {
        // 这里会触发文件选择对话框
        // 在实际SwiftUI实现中会使用 NSOpenPanel
    }
    
    // MARK: - Scanning Operations
    
    /// 开始扫描
    func startScan() {
        guard let url = selectedDirectoryURL else {
            setError("请先选择要扫描的目录")
            return
        }
        
        // 取消之前的扫描
        cancelScan()
        
        scanTask = Task {
            do {
                let startTime = Date()
                let treeNode = try await fileSystemService.scanDirectory(at: url)
                
                await MainActor.run {
                    self.rootNode = treeNode
                    self.updateScanStatistics(for: treeNode, scanTime: Date().timeIntervalSince(startTime))
                }
                
            } catch {
                await MainActor.run {
                    self.handleScanError(error)
                }
            }
        }
    }
    
    /// 取消扫描
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        fileSystemService.cancelCurrentScan()
    }
    
    /// 重新扫描
    func rescan() {
        guard selectedDirectoryURL != nil else { return }
        startScan()
    }
    
    // MARK: - Error Handling
    
    private func setError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
    
    private func handleScanError(_ error: Error) {
        if let fsError = error as? FileSystemError {
            errorMessage = fsError.userFriendlyMessage
            
            if fsError.isPermissionError {
                showPermissionAlert = true
            } else {
                showErrorAlert = true
            }
        } else {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
    
    /// 请求权限
    func requestPermission() {
        if fileSystemService.requestFullDiskAccess() {
            showPermissionAlert = false
            // 权限获取成功，重新尝试扫描
            if selectedDirectoryURL != nil {
                startScan()
            }
        } else {
            setError("需要完全磁盘访问权限才能扫描系统目录")
        }
    }
    
    // MARK: - Statistics
    
    private func updateScanStatistics(for node: TreeNode, scanTime: TimeInterval) {
        var stats = ScanStatistics()
        
        // 递归统计
        node.preorderTraversal { treeNode in
            let item = treeNode.fileSystemItem
            
            if item.isDirectory {
                stats.directoryCount += 1
            } else {
                stats.fileCount += 1
                stats.totalSize += item.size
            }
            
            // 按类型统计
            let category = item.fileType.category
            stats.categoryCounts[category, default: 0] += 1
            stats.categorySizes[category, default: 0] += item.size
        }
        
        stats.scanTime = scanTime
        stats.scanDepth = calculateMaxDepth(node)
        
        self.scanStatistics = stats
    }
    
    private func calculateMaxDepth(_ node: TreeNode) -> Int {
        if node.children.isEmpty {
            return 0
        }
        return 1 + node.children.map { calculateMaxDepth($0) }.max()!
    }
    
    // MARK: - Filtering
    
    /// 应用过滤器到树节点
    /// - Parameter node: 要过滤的树节点
    /// - Returns: 过滤后的树节点
    func applyFilters(to node: TreeNode) -> TreeNode? {
        return node.filter { treeNode in
            let item = treeNode.fileSystemItem
            
            // 隐藏文件过滤
            if !showHiddenFiles && item.name.hasPrefix(".") {
                return false
            }
            
            // 文件类型过滤
            if !fileTypeFilters.contains(item.fileType) {
                return false
            }
            
            // 文件大小过滤
            if !fileSizeFilter.matches(size: item.totalSize) {
                return false
            }
            
            return true
        }
    }
    
    /// 切换文件类型过滤器
    /// - Parameter fileType: 要切换的文件类型
    func toggleFileTypeFilter(_ fileType: FileType) {
        if fileTypeFilters.contains(fileType) {
            fileTypeFilters.remove(fileType)
        } else {
            fileTypeFilters.insert(fileType)
        }
    }
    
    /// 重置所有过滤器
    func resetFilters() {
        showHiddenFiles = false
        fileSizeFilter = .all
        fileTypeFilters = Set(FileType.allCases)
        maxScanDepth = 20
    }
    
    // MARK: - Navigation
    
    /// 导航到指定节点
    /// - Parameter node: 目标节点
    func navigateTo(node: TreeNode) {
        // 这里会更新UI状态，显示指定节点的详细信息
        // 在实际实现中会与TreeMapViewModel协调
    }
    
    /// 获取节点的面包屑路径
    /// - Parameter node: 目标节点
    /// - Returns: 路径组件数组
    func getBreadcrumbs(for node: TreeNode) -> [TreeNode] {
        return node.pathFromRoot
    }
}

// MARK: - Supporting Types

/// 扫描统计信息
struct ScanStatistics {
    var fileCount: Int = 0
    var directoryCount: Int = 0
    var totalSize: Int64 = 0
    var scanTime: TimeInterval = 0
    var scanDepth: Int = 0
    var categoryCounts: [FileCategory: Int] = [:]
    var categorySizes: [FileCategory: Int64] = [:]
    
    /// 格式化的总大小
    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// 格式化的扫描时间
    var formattedScanTime: String {
        return String(format: "%.2f秒", scanTime)
    }
    
    /// 总项目数
    var totalItems: Int {
        return fileCount + directoryCount
    }
    
    /// 获取最大的文件类别
    var largestCategory: (category: FileCategory, size: Int64)? {
        return categorySizes.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}

/// 文件大小过滤器
enum FileSizeFilter: String, CaseIterable {
    case all = "all"
    case small = "small"      // < 1MB
    case medium = "medium"    // 1MB - 100MB
    case large = "large"      // 100MB - 1GB
    case huge = "huge"        // > 1GB
    
    var displayName: String {
        switch self {
        case .all: return "所有大小"
        case .small: return "小文件 (< 1MB)"
        case .medium: return "中等文件 (1-100MB)"
        case .large: return "大文件 (100MB-1GB)"
        case .huge: return "巨大文件 (> 1GB)"
        }
    }
    
    func matches(size: Int64) -> Bool {
        let mb = Int64(1024 * 1024)
        let gb = mb * 1024
        
        switch self {
        case .all:
            return true
        case .small:
            return size < mb
        case .medium:
            return size >= mb && size < 100 * mb
        case .large:
            return size >= 100 * mb && size < gb
        case .huge:
            return size >= gb
        }
    }
}
