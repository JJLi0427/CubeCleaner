import Foundation
import Combine
import SwiftUI
import Darwin

// MARK: - 批量文件属性结构
/**
 * 用于getattrlistbulk批量获取文件属性的结构体
 * 这个结构体包含了文件扫描需要的所有关键属性，优化内存使用
 */
struct BulkFileAttributes {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date
    let path: String
}

// MARK: - 批量文件扫描器
/**
 * 使用getattrlistbulk API进行高效文件扫描的类
 * 相比传统的逐个文件扫描，批量API可以显著提升性能
 * 
 * 性能优势：
 * - 减少系统调用次数：一次调用获取多个文件属性
 * - 降低上下文切换开销：批量处理减少内核态/用户态切换
 * - 优化内存使用：使用固定大小缓冲区，避免内存碎片
 * - 提升缓存命中率：连续读取文件属性，提高磁盘缓存效率
 */
class BulkFileScanner {
    
    // 批量处理的文件数量，平衡内存使用和性能
    private static let batchSize: Int = 512
    
    // 缓冲区大小：64KB，优化内存使用和IO性能
    private static let bufferSize: Int = 64 * 1024
    
    /**
     * 使用getattrlistbulk批量扫描目录内容
     * @param directoryPath: 要扫描的目录路径
     * @returns: 包含文件属性的数组
     * @throws: 文件系统访问错误
     */
    static func scanDirectory(at directoryPath: String) throws -> [BulkFileAttributes] {
        let dirFD = open(directoryPath, O_RDONLY)
        guard dirFD >= 0 else {
            throw POSIXError(.EACCES)
        }
        defer { close(dirFD) }
        
        // 设置要获取的属性列表
        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        
        // 文件系统属性
        attrList.commonattr = UInt32(ATTR_CMN_NAME |
                                   ATTR_CMN_OBJTYPE |
                                   ATTR_CMN_CRTIME |
                                   ATTR_CMN_MODTIME)
        
        // 文件属性
        attrList.fileattr = UInt32(ATTR_FILE_DATALENGTH)
        
        var fileAttributes: [BulkFileAttributes] = []
        var buffer = [UInt8](repeating: 0, count: bufferSize) // 使用预定义的缓冲区大小
        
        while true {
            // 调用getattrlistbulk获取批量文件属性
            let count = buffer.withUnsafeMutableBytes { bufferPtr in
                getattrlistbulk(dirFD, &attrList, bufferPtr.baseAddress, bufferPtr.count, 0)
            }
            
            if count == 0 {
                break // 没有更多文件
            }
            
            if count < 0 {
                let error = errno
                if error == ENOENT || error == ENOTDIR {
                    break // 目录不存在或不是目录，正常结束
                }
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EACCES)
            }
            
            // 解析缓冲区中的属性数据
            let parsedFiles = try parseAttributeBuffer(buffer, count: Int(count), basePath: directoryPath)
            fileAttributes.append(contentsOf: parsedFiles)
            
            // 如果返回的文件数少于期望，说明已经读完
            if count < batchSize {
                break
            }
        }
        
        return fileAttributes
    }
    
    /**
     * 解析getattrlistbulk返回的属性缓冲区
     * @param buffer: 包含属性数据的缓冲区
     * @param count: 返回的文件数量
     * @param basePath: 基础路径
     * @returns: 解析后的文件属性数组
     */
    private static func parseAttributeBuffer(_ buffer: [UInt8], count: Int, basePath: String) throws -> [BulkFileAttributes] {
        var fileAttributes: [BulkFileAttributes] = []
        var offset = 0
        
        for _ in 0..<count {
            guard offset < buffer.count else { break }
            
            // 读取当前条目的长度
            let entryLength = buffer.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: UInt32.self)
            }
            
            guard offset + Int(entryLength) <= buffer.count else { break }
            
            let entryData = Array(buffer[offset..<offset + Int(entryLength)])
            
            do {
                let attributes = try parseFileAttributes(from: entryData, basePath: basePath)
                fileAttributes.append(attributes)
            } catch {
                // 跳过解析失败的条目，继续处理下一个
                print("跳过解析失败的文件条目: \(error)")
            }
            
            offset += Int(entryLength)
        }
        
        return fileAttributes
    }
    
    /**
     * 从单个文件的属性数据中解析文件信息
     * @param data: 文件属性数据
     * @param basePath: 基础路径
     * @returns: 解析后的文件属性
     */
    private static func parseFileAttributes(from data: [UInt8], basePath: String) throws -> BulkFileAttributes {
        var offset = 4 // 跳过长度字段
        
        // 读取文件名
        guard offset + 4 <= data.count else {
            throw FileSystemError.invalidPath
        }
        
        let nameInfo = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: attrreference.self)
        }
        offset += MemoryLayout<attrreference>.size
        
        let nameOffset = Int(nameInfo.attr_dataoffset)
        let nameLength = Int(nameInfo.attr_length)
        
        guard nameOffset + nameLength <= data.count else {
            throw FileSystemError.invalidPath
        }
        
        let nameData = Array(data[nameOffset..<nameOffset + nameLength])
        let fileName = String(cString: nameData) // C字符串以null结尾
        
        // 读取文件类型
        guard offset + 4 <= data.count else {
            throw FileSystemError.invalidPath
        }
        
        let objType = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        
        let isDirectory = (objType == VDIR.rawValue)
        
        // 读取创建时间
        guard offset + MemoryLayout<timespec>.size <= data.count else {
            throw FileSystemError.invalidPath
        }
        
        let creationTime = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: timespec.self)
        }
        offset += MemoryLayout<timespec>.size
        
        // 读取修改时间
        guard offset + MemoryLayout<timespec>.size <= data.count else {
            throw FileSystemError.invalidPath
        }
        
        let modificationTime = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: timespec.self)
        }
        offset += MemoryLayout<timespec>.size
        
        // 读取文件大小（仅对普通文件有效）
        var fileSize: Int64 = 0
        if !isDirectory {
            guard offset + 8 <= data.count else {
                throw FileSystemError.invalidPath
            }
            
            fileSize = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: Int64.self)
            }
        }
        
        // 构造完整路径
        let fullPath = (basePath as NSString).appendingPathComponent(fileName)
        
        // 转换时间戳为Date对象
        let creationDate = Date(timeIntervalSince1970: Double(creationTime.tv_sec) + Double(creationTime.tv_nsec) / 1_000_000_000)
        let modificationDate = Date(timeIntervalSince1970: Double(modificationTime.tv_sec) + Double(modificationTime.tv_nsec) / 1_000_000_000)
        
        return BulkFileAttributes(
            name: fileName,
            size: fileSize,
            isDirectory: isDirectory,
            creationDate: creationDate,
            modificationDate: modificationDate,
            path: fullPath
        )
    }
}

// MARK: - 文件系统项目数据模型
struct FileSystemItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date
    
    init(name: String, path: URL, size: Int64, isDirectory: Bool, creationDate: Date, modificationDate: Date) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var isHidden: Bool {
        name.hasPrefix(".")
    }
    
    var fileExtension: String {
        path.pathExtension.lowercased()
    }
}

// MARK: - 树节点模型
class TreeNode: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    @Published var children: [TreeNode] = []
    @Published var isExpanded: Bool = false
    
    var level: Int {
        (parent?.level ?? -1) + 1
    }
    
    var totalSize: Int64 {
        if item.isDirectory {
            return children.reduce(item.size) { $0 + $1.totalSize }
        }
        return item.size
    }
    
    init(item: FileSystemItem, parent: TreeNode? = nil) {
        self.item = item
        self.parent = parent
    }
    
    func addChild(_ child: TreeNode) {
        children.append(child)
    }
    
    func removeChild(_ child: TreeNode) {
        children.removeAll { $0.id == child.id }
    }
    
    func sortChildren(by comparison: (TreeNode, TreeNode) -> Bool) {
        children.sort(by: comparison)
        children.forEach { $0.sortChildren(by: comparison) }
    }
    
    // MARK: - Equatable
    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - 文件类型枚举
enum FileType: String, CaseIterable {
    case document, image, video, audio, archive, application, system, other
    
    static func from(extension: String) -> FileType {
        let ext = `extension`.lowercased()
        switch ext {
        case "txt", "pdf", "doc", "docx", "rtf", "md", "pages", "numbers", "keynote":
            return .document
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp", "heic", "raw":
            return .image
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "m4v", "3gp", "webm":
            return .video
        case "mp3", "wav", "aac", "flac", "ogg", "m4a", "wma", "aiff":
            return .audio
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso":
            return .archive
        case "app", "exe", "msi", "pkg", "deb", "rpm":
            return .application
        case "dylib", "framework", "bundle", "so", "dll", "lib", "a":
            return .system
        default:
            return .other
        }
    }
    
    var displayName: String {
        switch self {
        case .document: return "文档"
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case .archive: return "压缩包"
        case .application: return "应用程序"
        case .system: return "系统文件"
        case .other: return "其他"
        }
    }
}

// MARK: - 颜色方案管理器
class ColorSchemeManager: ObservableObject {
    static let shared = ColorSchemeManager()
    
    private let fileTypeColors: [FileType: Color] = [
        .document: .blue,
        .image: .green,
        .video: .red,
        .audio: .purple,
        .archive: .orange,
        .application: .gray,
        .system: .yellow,
        .other: Color(.systemGray)
    ]
    
    private let directoryColor: Color = .brown
    
    private init() {}
    
    func color(for node: TreeNode) -> Color {
        if node.item.isDirectory {
            return directoryColor.opacity(0.7)
        }
        
        let fileType = FileType.from(extension: node.item.fileExtension)
        return fileTypeColors[fileType] ?? .gray
    }
    
    func color(for fileType: FileType) -> Color {
        return fileTypeColors[fileType] ?? .gray
    }
    
    func colorForDirectory() -> Color {
        return directoryColor
    }
    
    // 根据文件大小调整颜色深度
    func adjustedColor(for node: TreeNode, maxSize: Int64) -> Color {
        let baseColor = color(for: node)
        
        if maxSize > 0 {
            let ratio = Double(node.totalSize) / Double(maxSize)
            let opacity = 0.3 + (ratio * 0.7) // 透明度范围 0.3 - 1.0
            return baseColor.opacity(opacity)
        }
        
        return baseColor.opacity(0.7)
    }
}

// MARK: - TreeMap矩形结构
struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let level: Int
    
    var shouldShowLabel: Bool {
        rect.width > 60 && rect.height > 25
    }
    
    var displayName: String {
        let maxLength = Int(rect.width / 8)
        if node.item.name.count > maxLength && maxLength > 3 {
            return String(node.item.name.prefix(maxLength - 3)) + "..."
        }
        return node.item.name
    }
    
    var canShowSize: Bool {
        rect.width > 100 && rect.height > 40
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file)
    }
}

// MARK: - TreeMap布局计算器
class TreeMapLayoutCalculator: ObservableObject {
    private let colorSchemeManager = ColorSchemeManager.shared
    private let minRectSize: CGFloat = 2.0 // 最小矩形大小
    private let maxDepth: Int = 5 // 最大显示深度
    
    func calculateLayout(for node: TreeNode, in rect: CGRect) -> [TreeMapRectangle] {
        guard rect.width >= minRectSize && rect.height >= minRectSize else {
            return []
        }
        
        return calculateLayoutRecursive(for: node, in: rect, level: 0)
    }
    
    private func calculateLayoutRecursive(for node: TreeNode, in rect: CGRect, level: Int) -> [TreeMapRectangle] {
        var rectangles: [TreeMapRectangle] = []
        
        // 如果是叶子节点或达到最大深度，创建矩形
        if node.children.isEmpty || level >= maxDepth {
            let maxSize = findMaxSize(in: node)
            let rectangle = TreeMapRectangle(
                node: node,
                rect: rect,
                color: colorSchemeManager.adjustedColor(for: node, maxSize: maxSize),
                level: level
            )
            rectangles.append(rectangle)
            return rectangles
        }
        
        // 过滤掉太小的子节点
        let validChildren = node.children.filter { $0.totalSize > 0 }
        guard !validChildren.isEmpty else {
            // 如果没有有效子节点，作为叶子节点处理
            let maxSize = findMaxSize(in: node)
            let rectangle = TreeMapRectangle(
                node: node,
                rect: rect,
                color: colorSchemeManager.adjustedColor(for: node, maxSize: maxSize),
                level: level
            )
            rectangles.append(rectangle)
            return rectangles
        }
        
        // 按大小排序子节点
        let sortedChildren = validChildren.sorted { $0.totalSize > $1.totalSize }
        
        // 使用简化的布局算法
        let childRectangles = layoutChildrenSimple(sortedChildren, in: rect, level: level + 1)
        rectangles.append(contentsOf: childRectangles)
        
        return rectangles
    }
    
    private func layoutChildrenSimple(_ children: [TreeNode], in rect: CGRect, level: Int) -> [TreeMapRectangle] {
        var rectangles: [TreeMapRectangle] = []
        let totalSize = children.reduce(0) { $0 + $1.totalSize }
        
        guard totalSize > 0 else { return rectangles }
        
        // 简单的垂直分割
        var currentY = rect.minY
        
        for child in children {
            let proportion = CGFloat(child.totalSize) / CGFloat(totalSize)
            let height = rect.height * proportion
            
            let childRect = CGRect(
                x: rect.minX,
                y: currentY,
                width: rect.width,
                height: height
            )
            
            // 递归计算子布局
            let childRectangles = calculateLayoutRecursive(for: child, in: childRect, level: level)
            rectangles.append(contentsOf: childRectangles)
            
            currentY += height
        }
        
        return rectangles
    }
    
    private func findMaxSize(in node: TreeNode) -> Int64 {
        if let parent = node.parent {
            return parent.children.map { $0.totalSize }.max() ?? node.totalSize
        }
        return node.totalSize
    }
}

// MARK: - 文件系统扫描服务
/**
 * 高性能文件系统扫描服务
 * 
 * 主要优化特性：
 * 1. 使用getattrlistbulk API进行批量文件属性获取，减少系统调用开销
 * 2. 内存优化：分批处理文件，避免内存峰值过高
 * 3. 异步处理：支持任务取消，不阻塞UI线程
 * 4. 错误处理：批量扫描失败时自动回退到传统方法
 * 5. 进度跟踪：实时更新扫描进度和统计信息
 */
@MainActor
class FileSystemService: ObservableObject {
    static let shared = FileSystemService()
    
    // MARK: - Published Properties
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var currentPath: String = ""
    @Published var filesScanned: Int = 0
    @Published var totalSize: Int64 = 0
    @Published var rootNode: TreeNode?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?
    private var estimatedTotalFiles: Int = 1000 // 用于进度估算
    
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
    
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        errorMessage = "扫描已取消"
    }
    
    func getAvailableVolumes() -> [URL] {
        return fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey
        ]) ?? []
    }
    
    // MARK: - Private Methods
    private func resetScanState() {
        isScanning = true
        scanProgress = 0.0
        filesScanned = 0
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
                // 先估算文件数量
                await estimateFileCount(at: url)
                
                // 扫描目录
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
    
    private func estimateFileCount(at url: URL) async {
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            estimatedTotalFiles = max(contents.count * 10, 1000) // 简单估算
        } catch {
            estimatedTotalFiles = 1000
        }
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
            let batchSize = 100 // 每批处理100个文件，平衡内存和性能
            
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
    private func processBatch(_ batch: [BulkFileAttributes], parentNode: TreeNode, currentDepth: Int) async {
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
            currentPath = item.path.path
            
            // 定期更新进度，减少UI更新频率
            if filesScanned % 50 == 0 {
                scanProgress = min(0.95, Double(filesScanned) / Double(estimatedTotalFiles))
            }
            
            // 递归扫描子目录
            if item.isDirectory {
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
                    .creationDateKey, .contentModificationDateKey
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
                    currentPath = item.path.path
                    
                    // 更新进度
                    if filesScanned % 50 == 0 {
                        scanProgress = min(0.95, Double(filesScanned) / Double(estimatedTotalFiles))
                    }
                    
                    // 递归扫描子目录
                    if item.isDirectory {
                        await scanRecursivelyFallback(node: childNode, currentDepth: currentDepth + 1)
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
    
    private func createFileSystemItem(from url: URL) throws -> FileSystemItem {
        let resourceValues = try url.resourceValues(forKeys: [
            .nameKey, .fileSizeKey, .isDirectoryKey,
            .creationDateKey, .contentModificationDateKey
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

// MARK: - 错误类型定义
enum FileSystemError: LocalizedError {
    case accessDenied
    case invalidPath
    case scanCancelled
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "无法访问所选文件夹，请检查权限设置"
        case .invalidPath:
            return "无效的文件路径"
        case .scanCancelled:
            return "扫描已被取消"
        }
    }
}

// MARK: - 数组扩展：支持批量处理
/**
 * 为Array添加chunked方法，用于将大数组分割成小批次处理
 * 这样可以优化内存使用，避免一次性处理太多数据
 */
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
