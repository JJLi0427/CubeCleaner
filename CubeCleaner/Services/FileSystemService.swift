// FileSystemService.swift — 文件系统扫描服务

import Combine
import Foundation

    // MARK: - 扫描去重键
    /// 文件系统对象唯一标识。目录用 `(st_dev, st_ino)`（需 lstat）；
    /// 普通文件直接用 bulk 返回的 `fileID`（已是 inode，零额外 syscall）。
    private struct VisitKey: Hashable {
        let dev: UInt64
        let ino: UInt64
    }

    // MARK: - 扫描进度（后台线程本地累加，节流回写主线程）
    /// 后台扫描线程就地累加的计数器，避免每项都 hop 主线程更新 @Published。
    /// 达到节流阈值（50 项或 100ms）时一次性同步到 FileSystemService 的 @Published。
    private struct ScanProgress {
        var filesScanned: Int = 0
        var folderCount: Int = 0
        var totalSize: Int64 = 0
        var currentPath: String = ""
        /// 上次回写主线程时的 filesScanned，用于判断是否到节流阈值
        var lastFlushedFiles: Int = 0
        /// 上次回写主线程的时间戳（DispatchTime）
        var lastFlushedTime: DispatchTime = .now()
    }

// MARK: FileSystemService - 文件系统扫描服务
/// 高性能文件系统扫描服务
///
/// 主要特性：
/// 1. 批量API优化：使用getattrlistbulk减少系统调用
/// 2. 内存管理：分批处理，控制内存峰值
/// 3. 后台扫描：阻塞 IO 与树构建跑在 Task.detached 后台线程，主线程仅做节流进度回写与最终接收（P0-3）
/// 4. 容错机制：批量扫描失败时自动回退
/// 5. 进度追踪：节流回写（50项/100ms）避免高频 @Published 写入
/// 6. 权限处理：安全的文件系统访问
/// 7. 卷边界：跨挂载点的子目录不递归，避免大小虚高（如 /System 带进 /System/Volumes/Data）
/// 8. 去重：硬链接/firmlink 同一对象只计一次（FR-006）
/// 9. 符号链接：不跟随，标记为叶子，避免环与幽灵条
@MainActor
class FileSystemService: ObservableObject {
    // MARK: - Published Properties
    @Published var isScanning = false
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
    func scanDirectory(at url: URL) {
        guard !isScanning else { return }

        // 重置状态
        resetScanState()

        // 阻塞 IO 与树构建跑在后台线程（Task.detached 不继承 @MainActor），
        // 保持主线程/UI 在扫描期间响应。结果回主线程接收。
        scanTask = Task.detached(priority: .utility) { [weak self] in
            await self?.performScanBackground(at: url)
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

    // MARK: - Private Methods
    private func resetScanState() {
        isScanning = true
        filesScanned = 0
        folderCount = 0
        totalSize = 0
        currentPath = ""
        errorMessage = nil
        rootNode = nil
    }

    /// 后台扫描入口（非 isolated，跑在 Task.detached 线程上）。
    /// security scope 配对在此 defer；整棵树后台构建（扫描期间无 SwiftUI 观察者，安全）；
    /// 节流回写进度；最后回主线程一次性赋 rootNode 并结束扫描。
    private nonisolated func performScanBackground(at url: URL) async {
        var progress = ScanProgress()
        var visited = Set<VisitKey>()
        // 挂载点集合：一次 getmntinfo 取全，后续 isMountPoint 走 O(1) 集合查找，
        // 避免 16 万目录每个都 statfs（实测 /System 省 ~233ms）。
        let mountPoints = buildMountPointSet()
        var root: TreeNode?
        var scanError: String?

        do {
            // security scope：进程级，start 后后台线程访问该 URL 下文件合法。
            guard url.startAccessingSecurityScopedResource() else {
                throw FileSystemError.accessDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            progress.currentPath = url.path
            _ = await flushProgress(progress)

            // 创建根节点（URLResourceValues 可在后台线程读）
            let rootItem = try createFileSystemItem(from: url)
            root = TreeNode(item: rootItem)

            // 根节点自身先入去重集合
            if let key = visitKey(forPath: url.path) {
                visited.insert(key)
            }

            if rootItem.isDirectory {
                await scanRecursively(node: root!, currentDepth: 0, visited: &visited, progress: &progress, mountPoints: mountPoints)
            }

            // 扫描后自底向上缓存一次聚合大小，此后 totalSize 均 O(1)（比较器/布局/统计不再递归）。
            root?.computeTotalSize()
            // 整树降序排序，提升 TreeMap 布局质量（大块在前）。纯内存操作，后台线程无副作用。
            root?.sortChildren { $0.totalSize > $1.totalSize }
        } catch {
            scanError = "扫描失败: \(error.localizedDescription)"
            print("扫描失败: \(error)")
        }

        // 最终回写：剩余进度 + rootNode + 结束状态，一次性到主线程
        await flushProgressFinal(progress, root: root, error: scanError)
    }

    /// 节流回写进度到 @Published。仅当距上次回写 ≥50 项或 ≥100ms 时 hop 主线程。
    /// 注意：progress 是值类型，调用方持有最新副本，节流时间戳更新交给调用方。
    private nonisolated func flushProgress(_ progress: ScanProgress) async -> ScanProgress? {
        let now = DispatchTime.now()
        let elapsed = now.uptimeNanoseconds &- progress.lastFlushedTime.uptimeNanoseconds
        let itemCount = progress.filesScanned &- progress.lastFlushedFiles
        guard itemCount >= 50 || elapsed >= 100_000_000 else { return nil }  // 50 项 或 100ms

        let files = progress.filesScanned
        let folders = progress.folderCount
        let total = progress.totalSize
        let path = progress.currentPath
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.filesScanned = files
            self.folderCount = folders
            self.totalSize = total
            self.currentPath = path
        }
        var updated = progress
        updated.lastFlushedFiles = files
        updated.lastFlushedTime = now
        return updated
    }

    /// 扫描结束时的最终回写：剩余进度 + rootNode + 结束状态。
    private nonisolated func flushProgressFinal(_ progress: ScanProgress, root: TreeNode?, error: String?) async {
        let files = progress.filesScanned
        let folders = progress.folderCount
        let total = progress.totalSize
        let path = progress.currentPath
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.filesScanned = files
            self.folderCount = folders
            self.totalSize = total
            self.currentPath = path
            if let error {
                self.errorMessage = error
            }
            self.rootNode = root
            self.isScanning = false
        }
    }

    /**
     * 使用优化的批量扫描算法递归扫描目录（非 isolated 同步递归，跑在后台线程）。
     *
     * 性能优化策略：
     * 1. 批量API：使用getattrlistbulk一次获取多个文件属性
     * 2. 内存管理：分批处理，控制内存使用峰值
     * 3. 错误恢复：批量扫描失败时自动回退到传统方法
     * 4. 取消支持：支持任务取消，避免无用的计算
     *
     * @param node: 要扫描的目录节点
     * @param currentDepth: 当前递归深度
     * @param visited: 已访问对象集合（去重）
     * @param progress: 进度计数器（节流回写主线程）
     * @param mountPoints: 挂载点路径集合（用于跨卷判断，O(1) 查找）
     */
    private nonisolated func scanRecursively(
        node: TreeNode, currentDepth: Int, visited: inout Set<VisitKey>, progress: inout ScanProgress,
        mountPoints: Set<String>
    ) async {
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
                await processBatch(batch, parentNode: node, currentDepth: currentDepth, visited: &visited, progress: &progress, mountPoints: mountPoints)

                // 节流回写进度（异步 hop 主线程，天然让出，无需 Task.yield）
                if let updated = await flushProgress(progress) {
                    progress = updated
                }
            }

        } catch {
            print("批量扫描目录失败 \(node.item.path): \(error)")
            // 回退到传统扫描方法
            await scanRecursivelyFallback(node: node, currentDepth: currentDepth, visited: &visited, progress: &progress)
        }
    }

    /**
     * 批量处理文件属性数据（非 isolated，后台线程）。
     * 内存优化策略：
     * - 分批处理：避免一次性加载大量文件到内存
     * - 即时处理：处理完一批后立即释放内存
     * @param batch: 当前批次的文件属性
     * @param parentNode: 父节点
     * @param currentDepth: 当前递归深度
     * @param visited: 已访问对象集合（去重）
     * @param progress: 进度计数器
     * @param mountPoints: 挂载点路径集合（O(1) 跨卷判断）
     */
    private nonisolated func processBatch(
        _ batch: [BulkFileAttributes], parentNode: TreeNode, currentDepth: Int,
        visited: inout Set<VisitKey>, progress: inout ScanProgress, mountPoints: Set<String>
    ) async {
        for attributes in batch {
            // 检查任务是否被取消
            guard !Task.isCancelled else { return }

            // 符号链接：不跟随，标记为叶子，不递归。其大小不计入统计。
            if attributes.isSymbolicLink {
                let item = FileSystemItem(
                    name: attributes.name,
                    path: URL(fileURLWithPath: attributes.path),
                    size: 0,
                    isDirectory: false
                )
                let childNode = TreeNode(item: item, parent: parentNode)
                childNode.markScanBoundary(.symlink)
                parentNode.addChild(childNode)
                progress.filesScanned += 1
                continue
            }

            // 创建FileSystemItem和TreeNode
            let item = FileSystemItem(
                name: attributes.name,
                path: URL(fileURLWithPath: attributes.path),
                size: attributes.size,
                isDirectory: attributes.isDirectory
            )

            let childNode = TreeNode(item: item, parent: parentNode)
            parentNode.addChild(childNode)

            // 目录与文件统一用 bulk 返回的 fileID 去重（已是 inode，零额外 syscall，免 lstat）。
            // 闸门顺序：符号链接已前置跳过；目录先判跨卷挂载点，再判去重。
            if attributes.isDirectory {
                progress.folderCount += 1

                // 闸门 1：跨挂载点 —— 子目录本身是另一个卷的挂载点（如 /System/Volumes/Data）。
                // 不递归，标为跨卷叶子，避免把整个数据卷算进来导致大小虚高。
                // 用预构建的 mountPoints 集合 O(1) 判断，替代每目录 statfs。
                if mountPoints.contains(attributes.path) {
                    childNode.markScanBoundary(.crossVolume)
                    progress.filesScanned += 1
                    continue
                }

                // 闸门 2：硬链接/firmlink 去重 —— 同一对象已在别处计入。
                // 目录用 bulk fileID 去重（与文件统一），免 lstat。
                // fileID 为 0 时（非 APFS 不可靠）跳过去重。
                if let fid = attributes.fileID, fid != 0 {
                    let key = VisitKey(dev: 0, ino: fid)
                    if visited.contains(key) {
                        childNode.markScanBoundary(.alreadyCounted)
                        progress.filesScanned += 1
                        continue
                    }
                    visited.insert(key)
                }

                progress.filesScanned += 1
                if progress.filesScanned % 20 == 0 {
                    progress.currentPath = item.path.path
                }

                await scanRecursively(node: childNode, currentDepth: currentDepth + 1, visited: &visited, progress: &progress, mountPoints: mountPoints)
            } else {
                // 普通文件：硬链接去重 —— 直接用 bulk 返回的 fileID（已是 inode），
                // 零额外 syscall（不必 lstat）。fileID 为 0 时（非 APFS 不可靠）跳过去重。
                progress.filesScanned += 1
                if let fid = attributes.fileID, fid != 0 {
                    let key = VisitKey(dev: 0, ino: fid)
                    if visited.contains(key) {
                        childNode.markScanBoundary(.alreadyCounted)
                        // 大小不计入 totalSize
                        if progress.filesScanned % 20 == 0 {
                            progress.currentPath = item.path.path
                        }
                        continue
                    }
                    visited.insert(key)
                }
                progress.totalSize += item.size
                if progress.filesScanned % 20 == 0 {
                    progress.currentPath = item.path.path
                }
            }
        }
    }

    /**
     * 传统扫描方法的回退实现（非 isolated，后台线程）
     * 当批量扫描失败时使用此方法保证兼容性
     * 同样应用跨挂载点 / 符号链接 / 去重三道闸门，保证回退路径行为一致。
     */
    private nonisolated func scanRecursivelyFallback(
        node: TreeNode, currentDepth: Int, visited: inout Set<VisitKey>, progress: inout ScanProgress
    ) async {
        // 限制扫描深度以避免过深递归和提高性能
        guard currentDepth < 10 else { return }

        // 检查任务是否被取消
        guard !Task.isCancelled else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: node.item.path,
                includingPropertiesForKeys: [
                    .nameKey, .fileSizeKey, .isDirectoryKey,
                ],
                options: [.skipsHiddenFiles]
            )

            for itemURL in contents {
                // 检查任务是否被取消
                guard !Task.isCancelled else { return }

                // 用 lstat 取真实类型与 inode（contentsOfDirectory 可能跟随符号链接）
                guard let (isDir, isLink, size) = lstatItem(at: itemURL.path) else { continue }

                // 符号链接：不跟随，标叶子。
                if isLink {
                    let item = FileSystemItem(
                        name: itemURL.lastPathComponent,
                        path: itemURL,
                        size: 0,
                        isDirectory: false
                    )
                    let childNode = TreeNode(item: item, parent: node)
                    childNode.markScanBoundary(.symlink)
                    node.addChild(childNode)
                    progress.filesScanned += 1
                    continue
                }

                let item = FileSystemItem(
                    name: itemURL.lastPathComponent,
                    path: itemURL,
                    size: Int64(size),
                    isDirectory: isDir
                )
                let childNode = TreeNode(item: item, parent: node)
                node.addChild(childNode)

                if isDir {
                    progress.folderCount += 1

                    // 闸门 1：跨挂载点
                    if isMountPoint(itemURL.path) {
                        childNode.markScanBoundary(.crossVolume)
                        progress.filesScanned += 1
                        continue
                    }

                    // 闸门 2：去重
                    if let key = visitKey(forPath: itemURL.path) {
                        if visited.contains(key) {
                            childNode.markScanBoundary(.alreadyCounted)
                            progress.filesScanned += 1
                            continue
                        }
                        visited.insert(key)
                    }

                    progress.filesScanned += 1
                    if progress.filesScanned % 20 == 0 {
                        progress.currentPath = item.path.path
                    }

                    await scanRecursivelyFallback(
                        node: childNode, currentDepth: currentDepth + 1, visited: &visited, progress: &progress)
                } else {
                    // 普通文件：用 lstat 取 inode 去重（回退路径无 bulk fileID，故仍 lstat）
                    progress.filesScanned += 1
                    if let key = visitKey(forPath: itemURL.path) {
                        if visited.contains(key) {
                            childNode.markScanBoundary(.alreadyCounted)
                            if progress.filesScanned % 20 == 0 {
                                progress.currentPath = item.path.path
                            }
                            continue
                        }
                        visited.insert(key)
                    }
                    progress.totalSize += item.size
                    if progress.filesScanned % 20 == 0 {
                        progress.currentPath = item.path.path
                    }
                }
            }

        } catch {
            print("无法扫描目录 \(node.item.path): \(error)")
        }
    }

    /// 创建FileSystemItem实例（nonisolated，后台线程可调）
    private nonisolated func createFileSystemItem(from url: URL) throws -> FileSystemItem {
        let resourceValues = try url.resourceValues(forKeys: [
            .nameKey, .fileSizeKey, .isDirectoryKey,
        ])

        return FileSystemItem(
            name: resourceValues.name ?? url.lastPathComponent,
            path: url,
            size: Int64(resourceValues.fileSize ?? 0),
            isDirectory: resourceValues.isDirectory ?? false
        )
    }

    // MARK: - 扫描边界 / 去重工具（nonisolated，可从后台线程调）

    /// 一次性取当前所有挂载点的 mntonname 集合。扫描开始时调一次，
    /// 之后跨卷判断走 O(1) 集合查找，避免 16 万目录每个都 statfs（实测 /System 省 ~233ms）。
    private nonisolated func buildMountPointSet() -> Set<String> {
        var set = Set<String>()
        var mntbuf: UnsafeMutablePointer<statfs>? = nil
        let count = getmntinfo(&mntbuf, 0)
        guard count > 0, let buf = mntbuf else { return set }
        for i in 0..<Int(count) {
            let mntonName = buf[i].f_mntonname
            let capacity = MemoryLayout.size(ofValue: mntonName)
            // f_mntonname 是 [CChar; MNAMELEN] 的 C 数组（Swift 里是元组）。拷贝到局部再取指针转 String，
            // 避免对 statfs 的重叠访问。
            let path = withUnsafePointer(to: mntonName) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            set.insert(path)
        }
        return set
    }

    /// 判断 path 是否是某个卷的挂载点：statfs(path).f_mntonname == path。
    /// 用于回退路径（FileManager，无预构建集合时）的跨挂载点判断。
    private nonisolated func isMountPoint(_ path: String) -> Bool {
        var s = statfs()
        let result = path.withCString { statfs($0, &s) }
        guard result == 0 else { return false }
        // f_mntonname 是 [CChar; MNAMELEN] 的 C 数组（Swift 里是元组）。先把元组拷贝到局部，
        // 再取指针转 String 比较，避免对 s 的重叠访问。
        let mntonName = s.f_mntonname
        let capacity = MemoryLayout.size(ofValue: mntonName)
        return withUnsafePointer(to: mntonName) { ptr -> Bool in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0) == path
            }
        }
    }

    /// 取 (st_dev, st_ino) 去重键。用 lstat（不跟随符号链接），失败返回 nil。
    /// 仅回退路径（FileManager）与根节点用——bulk 路径已用 bulk 返回的 fileID 去重，免 lstat。
    private nonisolated func visitKey(forPath path: String) -> VisitKey? {
        var st = stat()
        let result = path.withCString { lstat($0, &st) }
        guard result == 0 else { return nil }
        return VisitKey(dev: UInt64(st.st_dev), ino: UInt64(st.st_ino))
    }

    /// 用 lstat 取 (是否目录, 是否符号链接, 文件大小)。不跟随符号链接。
    private nonisolated func lstatItem(at path: String) -> (isDir: Bool, isLink: Bool, size: Int64)? {
        var st = stat()
        let result = path.withCString { lstat($0, &st) }
        guard result == 0 else { return nil }
        let mode = st.st_mode
        let isLink = (mode & S_IFMT) == S_IFLNK
        let isDir = (mode & S_IFMT) == S_IFDIR
        return (isDir, isLink, Int64(st.st_size))
    }
}
