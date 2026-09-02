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

    // MARK: - 扫描进度
    /// 后台扫描线程就地累加的计数器，避免每项都 hop 主线程更新 @Published。
    /// 达到节流阈值（50 项或 100ms）时一次性同步到 FileSystemService 的 @Published。
    private struct ScanProgress {
        var filesScanned: Int = 0
        var folderCount: Int = 0
        var totalSize: Int64 = 0
        var currentPath: String = ""
        var lastFlushedFiles: Int = 0
        var lastFlushedTime: DispatchTime = .now()
    }

// MARK: FileSystemService - 文件系统扫描服务
/// 高性能文件系统扫描：getattrlistbulk 批量读取、后台线程、节流进度回写、
/// 硬链接/firmlink 去重、跨卷边界、符号链接不跟随。
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
        resetScanState()

        // 阻塞 IO 与树构建跑在后台线程（Task.detached 不继承 @MainActor）。
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

    /// 后台扫描入口（nonisolated，跑在 Task.detached 线程）。
    private nonisolated func performScanBackground(at url: URL) async {
        var progress = ScanProgress()
        var visited = Set<VisitKey>()
        // 挂载点集合：一次 getmntinfo 取全，之后 isMountPoint 走 O(1) 集合查找。
        let mountPoints = buildMountPointSet()
        var root: TreeNode?
        var scanError: String?

        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw FileSystemError.accessDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            progress.currentPath = url.path
            _ = await flushProgress(progress)

            let rootItem = try createFileSystemItem(from: url)
            root = TreeNode(item: rootItem)

            if let key = visitKey(forPath: url.path) {
                visited.insert(key)
            }

            if rootItem.isDirectory {
                await scanRecursively(node: root!, currentDepth: 0, visited: &visited, progress: &progress, mountPoints: mountPoints)
            }

            // 扫描后自底向上缓存一次聚合大小，此后 totalSize 均 O(1)。
            root?.computeTotalSize()
            // 整树降序排序，提升 TreeMap 布局质量（大块在前）。
            root?.sortChildren { $0.totalSize > $1.totalSize }
        } catch {
            scanError = "扫描失败: \(error.localizedDescription)"
            print("扫描失败: \(error)")
        }

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
     * 使用批量扫描算法递归扫描目录（nonisolated 同步递归，跑在后台线程）。
     * 批量扫描失败时回退到 FileManager 传统方法。
     */
    private nonisolated func scanRecursively(
        node: TreeNode, currentDepth: Int, visited: inout Set<VisitKey>, progress: inout ScanProgress,
        mountPoints: Set<String>
    ) async {
        guard currentDepth < 10 else { return }
        guard !Task.isCancelled else { return }

        do {
            let bulkAttributes = try BulkFileScanner.scanDirectory(at: node.item.path.path)
            let batchSize = 100

            for batch in bulkAttributes.chunked(into: batchSize) {
                guard !Task.isCancelled else { return }
                await processBatch(batch, parentNode: node, currentDepth: currentDepth, visited: &visited, progress: &progress, mountPoints: mountPoints)

                // 节流回写进度（异步 hop 主线程，天然让出，无需 Task.yield）
                if let updated = await flushProgress(progress) {
                    progress = updated
                }
            }

        } catch {
            print("批量扫描目录失败 \(node.item.path): \(error)")
            await scanRecursivelyFallback(node: node, currentDepth: currentDepth, visited: &visited, progress: &progress)
        }
    }

    /**
     * 批量处理文件属性数据（nonisolated，后台线程）。
     */
    private nonisolated func processBatch(
        _ batch: [BulkFileAttributes], parentNode: TreeNode, currentDepth: Int,
        visited: inout Set<VisitKey>, progress: inout ScanProgress, mountPoints: Set<String>
    ) async {
        for attributes in batch {
            guard !Task.isCancelled else { return }

            // 符号链接：不跟随，标记为叶子，大小不计入统计。
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

            let item = FileSystemItem(
                name: attributes.name,
                path: URL(fileURLWithPath: attributes.path),
                size: attributes.size,
                isDirectory: attributes.isDirectory
            )

            let childNode = TreeNode(item: item, parent: parentNode)
            parentNode.addChild(childNode)

            // 目录与文件统一用 bulk 返回的 fileID 去重（已是 inode，零额外 syscall，免 lstat）。
            if attributes.isDirectory {
                progress.folderCount += 1

                // 闸门 1：跨挂载点 —— 不递归，标为跨卷叶子。
                if mountPoints.contains(attributes.path) {
                    childNode.markScanBoundary(.crossVolume)
                    progress.filesScanned += 1
                    continue
                }

                // 闸门 2：硬链接/firmlink 去重。fileID 为 0 时（非 APFS 不可靠）跳过去重。
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
                // 普通文件：硬链接去重，直接用 bulk 返回的 fileID。
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
     * 传统扫描方法的回退实现（nonisolated，后台线程）。
     * 当批量扫描失败时使用此方法保证兼容性。
     */
    private nonisolated func scanRecursivelyFallback(
        node: TreeNode, currentDepth: Int, visited: inout Set<VisitKey>, progress: inout ScanProgress
    ) async {
        guard currentDepth < 10 else { return }
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
                guard !Task.isCancelled else { return }

                // 用 lstat 取真实类型与 inode（contentsOfDirectory 可能跟随符号链接）
                guard let (isDir, isLink, size) = lstatItem(at: itemURL.path) else { continue }

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

                    if isMountPoint(itemURL.path) {
                        childNode.markScanBoundary(.crossVolume)
                        progress.filesScanned += 1
                        continue
                    }

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
                    // 普通文件：用 lstat 取 inode 去重（回退路径无 bulk fileID）
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

    /// 一次性取当前所有挂载点的 mntonname 集合，之后跨卷判断走 O(1) 集合查找。
    private nonisolated func buildMountPointSet() -> Set<String> {
        var set = Set<String>()
        var mntbuf: UnsafeMutablePointer<statfs>? = nil
        let count = getmntinfo(&mntbuf, 0)
        guard count > 0, let buf = mntbuf else { return set }
        for i in 0..<Int(count) {
            let mntonName = buf[i].f_mntonname
            let capacity = MemoryLayout.size(ofValue: mntonName)
            // f_mntonname 是 [CChar; MNAMELEN] 的 C 数组，拷贝到局部再取指针转 String。
            let path = withUnsafePointer(to: mntonName) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            set.insert(path)
        }
        return set
    }

    /// 判断 path 是否是某个卷的挂载点：statfs(path).f_mntonname == path（回退路径用）。
    private nonisolated func isMountPoint(_ path: String) -> Bool {
        var s = statfs()
        let result = path.withCString { statfs($0, &s) }
        guard result == 0 else { return false }
        let mntonName = s.f_mntonname
        let capacity = MemoryLayout.size(ofValue: mntonName)
        return withUnsafePointer(to: mntonName) { ptr -> Bool in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0) == path
            }
        }
    }

    /// 取 (st_dev, st_ino) 去重键，用 lstat（不跟随符号链接），失败返回 nil。
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
