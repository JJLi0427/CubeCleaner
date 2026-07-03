// FileSystemService.swift — 文件系统扫描服务

import Combine
import Foundation

// MARK: - 文件系统服务模块
// MARK: FileSystemService - 文件系统扫描服务
/// 高性能文件系统扫描服务
///
/// 主要特性：
/// 1. 批量API优化：使用getattrlistbulk减少系统调用
/// 2. 内存管理：分批处理，控制内存峰值
/// 3. 异步处理：支持任务取消，保持UI响应
/// 4. 容错机制：批量扫描失败时自动回退
/// 5. 进度追踪：实时更新扫描状态和统计
/// 6. 权限处理：安全的文件系统访问
@MainActor
class FileSystemService: ObservableObject {
    static let shared = FileSystemService()

    // MARK: - Published Properties
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var currentPath: String = ""
    @Published var filesScanned: Int = 0
    @Published var folderCount: Int = 0
    @Published var totalSize: Int64 = 0
    @Published var rootNode: TreeNode?
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?

    init() {}

    // MARK: - Public Methods
    func scanDirectory(at url: URL) {
        guard !isScanning else { return }

        // 重置状态
        resetScanState()

        scanTask = Task {
            await performScan(at: url)
        }
    }

    /// 移到废纸篓后重扫扫描根，使 TreeMap/统计/图例同步。
    /// trashItem 需 read-write entitlement。
    func trashAndRescan(deleteURL: URL, scanRootURL: URL?) {
        Task {
            do {
                var resultingURL: NSURL?
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: deleteURL, resultingItemURL: &resultingURL)
                }.value
                if let scanRoot = scanRootURL {
                    scanDirectory(at: scanRoot)
                }
            } catch {
                errorMessage = "删除失败: \(error.localizedDescription)"
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        errorMessage = "扫描已取消"
    }

    func getAvailableVolumes() -> [URL] {
        return fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
        ]) ?? []
    }

    // MARK: - Private Methods
    private func resetScanState() {
        isScanning = true
        scanProgress = 0.0
        filesScanned = 0
        folderCount = 0
        totalSize = 0
        currentPath = ""
        errorMessage = nil
        rootNode = nil
    }

    private func performScan(at url: URL) async {
        do {
            currentPath = url.path

            // 请求访问权限
            guard url.startAccessingSecurityScopedResource() else {
                throw FileSystemError.accessDenied
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            // 创建根节点
            let rootItem = try createFileSystemItem(from: url)
            let root = TreeNode(item: rootItem)

            if rootItem.isDirectory {
                // 扫描目录（总数未知，UI 用不确定进度条 + 实时计数）
                await scanRecursively(node: root, currentDepth: 0)
            }

            rootNode = root
            scanProgress = 1.0

        } catch {
            errorMessage = "扫描失败: \(error.localizedDescription)"
            print("扫描失败: \(error)")
        }

        isScanning = false
    }

    /**
     * 使用优化的批量扫描算法递归扫描目录
     *
     * 性能优化策略：
     * 1. 批量API：使用getattrlistbulk一次获取多个文件属性
     * 2. 内存管理：分批处理文件，控制内存使用峰值
     * 3. 异步处理：定期让出执行权，保持UI响应性
     * 4. 错误恢复：批量扫描失败时自动回退到传统方法
     * 5. 取消支持：支持任务取消，避免无用的计算
     *
     * @param node: 要扫描的目录节点
     * @param currentDepth: 当前递归深度
     */
    private func scanRecursively(node: TreeNode, currentDepth: Int) async {
        // 限制扫描深度以避免过深递归和提高性能
        guard currentDepth < 10 else { return }

        // 检查任务是否被取消
        guard !Task.isCancelled else { return }

        do {
            // 使用批量扫描API获取目录内容
            let bulkAttributes = try BulkFileScanner.scanDirectory(at: node.item.path.path)

            // 内存优化：使用懒加载和批处理
            let batchSize = 100  // 每批处理100个文件，平衡内存和性能

            for batch in bulkAttributes.chunked(into: batchSize) {
                // 检查任务是否被取消
                guard !Task.isCancelled else { return }

                // 批量处理文件
                await processBatch(batch, parentNode: node, currentDepth: currentDepth)

                // 让出执行权，避免阻塞UI
                await Task.yield()
            }

        } catch {
            print("批量扫描目录失败 \(node.item.path): \(error)")
            // 回退到传统扫描方法
            await scanRecursivelyFallback(node: node, currentDepth: currentDepth)
        }
    }

    /**
     * 批量处理文件属性数据
     * 内存优化策略：
     * - 分批处理：避免一次性加载大量文件到内存
     * - 即时处理：处理完一批后立即释放内存
     * - 让出执行权：使用Task.yield()避免阻塞主线程
     * @param batch: 当前批次的文件属性
     * @param parentNode: 父节点
     * @param currentDepth: 当前递归深度
     */
    private func processBatch(
        _ batch: [BulkFileAttributes], parentNode: TreeNode, currentDepth: Int
    ) async {
        for attributes in batch {
            // 检查任务是否被取消
            guard !Task.isCancelled else { return }

            // 创建FileSystemItem和TreeNode
            let item = FileSystemItem(
                name: attributes.name,
                path: URL(fileURLWithPath: attributes.path),
                size: attributes.size,
                isDirectory: attributes.isDirectory,
                creationDate: attributes.creationDate,
                modificationDate: attributes.modificationDate
            )

            let childNode = TreeNode(item: item, parent: parentNode)
            parentNode.addChild(childNode)

            // 更新统计信息
            filesScanned += 1
            totalSize += item.size
            // 每 20 项刷新一次当前路径，让计数与路径更连续地滚动(不确定进度条)
            if filesScanned % 20 == 0 {
                currentPath = item.path.path
            }

            // 递归扫描子目录
            if item.isDirectory {
                folderCount += 1
                await scanRecursively(node: childNode, currentDepth: currentDepth + 1)
            }
        }
    }

    /**
     * 传统扫描方法的回退实现
     * 当批量扫描失败时使用此方法保证兼容性
     */
    private func scanRecursivelyFallback(node: TreeNode, currentDepth: Int) async {
        // 限制扫描深度以避免过深递归和提高性能
        guard currentDepth < 10 else { return }

        // 检查任务是否被取消
        guard !Task.isCancelled else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: node.item.path,
                includingPropertiesForKeys: [
                    .nameKey, .fileSizeKey, .isDirectoryKey,
                    .creationDateKey, .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )

            for itemURL in contents {
                // 检查任务是否被取消
                guard !Task.isCancelled else { return }

                do {
                    let item = try createFileSystemItem(from: itemURL)
                    let childNode = TreeNode(item: item, parent: node)
                    node.addChild(childNode)

                    // 更新统计信息
                    filesScanned += 1
                    totalSize += item.size
                    if filesScanned % 20 == 0 {
                        currentPath = item.path.path
                    }

                    // 递归扫描子目录
                    if item.isDirectory {
                        folderCount += 1
                        await scanRecursivelyFallback(
                            node: childNode, currentDepth: currentDepth + 1)
                    }

                } catch {
                    // 跳过无法访问的文件，继续扫描其他文件
                    continue
                }
            }

        } catch {
            print("无法扫描目录 \(node.item.path): \(error)")
        }
    }

    /// 创建FileSystemItem实例
    private func createFileSystemItem(from url: URL) throws -> FileSystemItem {
        let resourceValues = try url.resourceValues(forKeys: [
            .nameKey, .fileSizeKey, .isDirectoryKey,
            .creationDateKey, .contentModificationDateKey,
        ])

        return FileSystemItem(
            name: resourceValues.name ?? url.lastPathComponent,
            path: url,
            size: Int64(resourceValues.fileSize ?? 0),
            isDirectory: resourceValues.isDirectory ?? false,
            creationDate: resourceValues.creationDate ?? Date(),
            modificationDate: resourceValues.contentModificationDate ?? Date()
        )
    }
}
