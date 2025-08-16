/**
 * CubeCleanerBackend.swift
 *
 * CubeCleaner文件系统分析后端服务
 *
 * 文件结构说明：
 * ├── 文件扫描模块 (Lines 1-350)
 * │   ├── BulkFileAttributes - 批量文件属性结构
 * │   ├── BulkFileScanner - 高性能批量文件扫描器
 * │   └── 相关工具函数
 * │
 * ├── 数据模型模块 (Lines 351-450)
 * │   ├── FileSystemItem - 文件系统项目数据模型
 * │   ├── TreeNode - 树节点模型
 * │   └── FileType - 文件类型枚举
 * │
 * ├── 可视化模块 (Lines 451-900)
 * │   ├── ColorSchemeManager - 颜色方案管理器
 * │   ├── TreeMapRectangle - TreeMap矩形结构
 * │   ├── TreeMapLayoutCalculator - Squarified TreeMap布局计算器
 * │   └── NormalizedItem - 规范化项目数据
 * │
 * ├── 文件系统服务模块 (Lines 901-1050)
 * │   ├── FileSystemService - 主要的文件系统扫描服务
 * │   └── 相关扫描和处理方法
 * │
 * └── 工具模块 (Lines 1051-END)
 *     ├── FileSystemError - 错误类型定义
 *     └── Array扩展 - 数组分块处理
 */

import Combine
import Darwin
import Foundation
import SwiftUI

// MARK: - 批量文件属性结构
/// 用于getattrlistbulk批量获取文件属性的结构体
/// 这个结构体包含了文件扫描需要的所有关键属性，优化内存使用
struct BulkFileAttributes {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date
    let path: String
}

// MARK: - 批量文件扫描器
/// 使用getattrlistbulk API进行高效文件扫描的类
/// 相比传统的逐个文件扫描，批量API可以显著提升性能
///
/// 性能优势：
/// - 减少系统调用次数：一次调用获取多个文件属性
/// - 降低上下文切换开销：批量处理减少内核态/用户态切换
/// - 优化内存使用：使用固定大小缓冲区，避免内存碎片
/// - 提升缓存命中率：连续读取文件属性，提高磁盘缓存效率
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
        attrList.commonattr = UInt32(
            ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_CRTIME | ATTR_CMN_MODTIME)

        // 文件属性
        attrList.fileattr = UInt32(ATTR_FILE_DATALENGTH)

        var fileAttributes: [BulkFileAttributes] = []
        var buffer = [UInt8](repeating: 0, count: bufferSize)  // 使用预定义的缓冲区大小

        while true {
            // 调用getattrlistbulk获取批量文件属性
            let count = buffer.withUnsafeMutableBytes { bufferPtr in
                getattrlistbulk(dirFD, &attrList, bufferPtr.baseAddress, bufferPtr.count, 0)
            }

            if count == 0 {
                break  // 没有更多文件
            }

            if count < 0 {
                let error = errno
                if error == ENOENT || error == ENOTDIR {
                    break  // 目录不存在或不是目录，正常结束
                }
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EACCES)
            }

            // 解析缓冲区中的属性数据
            let parsedFiles = try parseAttributeBuffer(
                buffer, count: Int(count), basePath: directoryPath)
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
    private static func parseAttributeBuffer(_ buffer: [UInt8], count: Int, basePath: String) throws
        -> [BulkFileAttributes]
    {
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
    private static func parseFileAttributes(from data: [UInt8], basePath: String) throws
        -> BulkFileAttributes
    {
        var offset = 4  // 跳过长度字段

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
        let fileName = String(cString: nameData)  // C字符串以null结尾

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
        let creationDate = Date(
            timeIntervalSince1970: Double(creationTime.tv_sec) + Double(creationTime.tv_nsec)
                / 1_000_000_000)
        let modificationDate = Date(
            timeIntervalSince1970: Double(modificationTime.tv_sec) + Double(
                modificationTime.tv_nsec) / 1_000_000_000)

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

// MARK: - 数据模型模块
// MARK: FileSystemItem - 文件系统项目数据模型
/// 文件系统项目的标准化数据结构
/// 包含文件/文件夹的基本属性和元数据
///
/// 特性：
/// - Identifiable: 支持SwiftUI列表显示
/// - Codable: 支持序列化存储
/// - Hashable: 支持集合操作
struct FileSystemItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date

    init(
        name: String, path: URL, size: Int64, isDirectory: Bool, creationDate: Date,
        modificationDate: Date
    ) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    /// 格式化的文件大小字符串
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// 是否为隐藏文件/文件夹
    var isHidden: Bool {
        name.hasPrefix(".")
    }

    /// 文件扩展名（小写）
    var fileExtension: String {
        path.pathExtension.lowercased()
    }
}

// MARK: TreeNode - 树形结构节点模型
/// 文件系统的树形结构节点
/// 支持递归遍历和层次化显示
///
/// 特性：
/// - ObservableObject: 支持SwiftUI数据绑定
/// - 父子关系维护
/// - 展开/折叠状态管理
/// - 递归大小计算
class TreeNode: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    @Published var children: [TreeNode] = []
    @Published var isExpanded: Bool = false

    /// 节点在树中的层级深度
    var level: Int {
        (parent?.level ?? -1) + 1
    }

    /// 递归计算总大小（包含所有子项）
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

    /// 添加子节点
    func addChild(_ child: TreeNode) {
        children.append(child)
    }

    /// 移除子节点
    func removeChild(_ child: TreeNode) {
        children.removeAll { $0.id == child.id }
    }

    /// 递归排序子节点
    func sortChildren(by comparison: (TreeNode, TreeNode) -> Bool) {
        children.sort(by: comparison)
        children.forEach { $0.sortChildren(by: comparison) }
    }

    // MARK: - Equatable
    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: FileType - 文件类型枚举
/// 文件类型分类枚举
/// 根据文件扩展名进行智能分类
///
/// 支持的类型：
/// - document: 文档类文件
/// - image: 图片类文件
/// - video: 视频类文件
/// - audio: 音频类文件
/// - archive: 压缩包类文件
/// - application: 应用程序类文件
/// - system: 系统类文件
/// - other: 其他类型文件
enum FileType: String, CaseIterable {
    case document, image, video, audio, archive, application, system, other

    /// 根据文件扩展名判断文件类型
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

    /// 本地化显示名称
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

// MARK: - 可视化模块
// MARK: ColorSchemeManager - 颜色方案管理器
/// 统一的颜色方案管理器
/// 负责为不同类型的文件和文件夹分配颜色
///
/// 特性：
/// - 单例模式，全局一致的颜色方案
/// - 基于文件类型的智能配色
/// - 支持动态透明度调整
/// - 文件夹和文件的区分显示
class ColorSchemeManager: ObservableObject {
    static let shared = ColorSchemeManager()

    /// 文件类型颜色映射表
    private let fileTypeColors: [FileType: Color] = [
        .document: .blue,
        .image: .green,
        .video: .red,
        .audio: .purple,
        .archive: .orange,
        .application: .gray,
        .system: .yellow,
        .other: Color(.systemGray),
    ]

    /// 文件夹专用颜色
    private let directoryColor: Color = .brown

    private init() {}

    /// 获取节点对应的颜色
    func color(for node: TreeNode) -> Color {
        if node.item.isDirectory {
            return directoryColor.opacity(0.7)
        }

        let fileType = FileType.from(extension: node.item.fileExtension)
        return fileTypeColors[fileType] ?? .gray
    }

    /// 获取文件类型对应的颜色
    func color(for fileType: FileType) -> Color {
        return fileTypeColors[fileType] ?? .gray
    }

    /// 获取文件夹颜色
    func colorForDirectory() -> Color {
        return directoryColor
    }

    /// 根据文件大小调整颜色深度
    func adjustedColor(for node: TreeNode, maxSize: Int64) -> Color {
        let baseColor = color(for: node)

        if maxSize > 0 {
            let ratio = Double(node.totalSize) / Double(maxSize)
            let opacity = 0.3 + (ratio * 0.7)  // 透明度范围 0.3 - 1.0
            return baseColor.opacity(opacity)
        }

        return baseColor.opacity(0.7)
    }
}

// MARK: TreeMapRectangle - TreeMap矩形结构
/// TreeMap可视化中的单个矩形元素
/// 包含显示逻辑和交互信息
///
/// 特性：
/// - 自适应标签显示：根据矩形大小决定显示内容
/// - 智能文本截断：保留重要信息（如文件扩展名）
/// - 分层显示控制：不同层级的显示策略
/// - 重要性判断：用于优化显示效果
struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let level: Int

    /**
     * 是否显示标签的判断逻辑
     * 基于矩形的实际可视大小，确保标签可读性
     */
    var shouldShowLabel: Bool {
        // 矩形需要足够大才显示标签
        return rect.width > 50 && rect.height > 20
    }

    /**
     * 智能显示名称
     * 根据可用空间自动调整显示内容
     */
    var displayName: String {
        let availableWidth = rect.width - 8  // 减去padding
        let estimatedCharWidth: CGFloat = 7  // 估算字符宽度
        let maxChars = Int(availableWidth / estimatedCharWidth)

        guard maxChars > 3 else { return "" }

        let name = node.item.name
        if name.count <= maxChars {
            return name
        } else {
            // 智能截断：保留文件扩展名
            if !node.item.isDirectory && name.contains(".") {
                let components = name.split(separator: ".", maxSplits: 1)
                if components.count == 2 {
                    let namepart = String(components[0])
                    let ext = String(components[1])
                    let availableForName = maxChars - ext.count - 4  // "...ext"
                    if availableForName > 0 {
                        return String(namepart.prefix(availableForName)) + "..." + ext
                    }
                }
            }
            // 普通截断
            return String(name.prefix(maxChars - 3)) + "..."
        }
    }

    /**
     * 是否显示大小信息
     * 只有在矩形足够大的情况下才显示
     */
    var canShowSize: Bool {
        return rect.width > 80 && rect.height > 35
    }

    /**
     * 是否显示详细信息（文件数量等）
     */
    var canShowDetails: Bool {
        return rect.width > 120 && rect.height > 50
    }

    /**
     * 格式化的大小字符串
     */
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file)
    }

    /**
     * 矩形的重要程度（用于决定显示优先级）
     * 基于大小和层级
     */
    var importance: Double {
        let sizeWeight = Double(node.totalSize)
        let levelWeight = 1.0 / Double(level + 1)  // 层级越深权重越小
        return sizeWeight * levelWeight
    }

    /**
     * 是否为重要节点（大文件/文件夹）
     */
    var isImportant: Bool {
        return node.totalSize > 10_000_000  // 大于10MB认为是重要的
    }

    /**
     * 获取子文件数量描述
     */
    var childrenDescription: String {
        guard node.item.isDirectory else { return "" }
        let count = node.children.count
        if count == 0 {
            return "空文件夹"
        } else {
            return "\(count) 项"
        }
    }
}

// MARK: - Squarified TreeMap 布局计算器
/// Squarified TreeMap算法实现
///
/// 算法特点：
/// 1. 保证图形完全密铺，无空隙
/// 2. 优化矩形纵横比，避免过窄或过宽的矩形
/// 3. 递归分割，保持层次结构清晰
/// 4. 动态选择最佳分割方向
///
/// 参考论文：Squarified Treemaps (Mark Bruls, Kees Huizing, Jarke J. van Wijk)
class TreeMapLayoutCalculator: ObservableObject {

    // MARK: - Configuration Constants
    private let colorSchemeManager = ColorSchemeManager.shared
    private let minRectSize: CGFloat = 6.0  // 最小可辨识矩形大小
    private let minAspectRatio: CGFloat = 0.3  // 最小纵横比阈值
    private let maxDepth: Int = 10  // 最大递归深度
    private let minSizeThreshold: Double = 0.001  // 最小大小占比阈值

    // MARK: - Global State for Better Algorithm
    private var globalMaxSize: Int64 = 0  // 全局最大大小，用于颜色归一化

    // MARK: - Public Interface
    /**
     * 计算TreeMap布局的主入口
     * @param node: 要布局的节点
     * @param rect: 可用的矩形区域
     * @return: 布局后的矩形数组
     */
    func calculateLayout(for node: TreeNode, in rect: CGRect) -> [TreeMapRectangle] {
        guard rect.width >= minRectSize && rect.height >= minRectSize else {
            return []
        }

        // Linus式修复：统一的全局状态管理，消除颜色归一化不一致问题
        globalMaxSize = findGlobalMaxSize(in: node)

        return squarifiedTreemap(for: node, in: rect, level: 0)
    }

    // MARK: - Core Squarified Algorithm
    /**
     * Squarified TreeMap核心算法
     * 递归实现密铺的矩形分割
     */
    private func squarifiedTreemap(for node: TreeNode, in rect: CGRect, level: Int)
        -> [TreeMapRectangle]
    {
        var rectangles: [TreeMapRectangle] = []

        // 终止条件检查
        if shouldTerminate(rect: rect, level: level, node: node) {
            let rectangle = createLeafRectangle(node: node, rect: rect, level: level)
            rectangles.append(rectangle)
            return rectangles
        }

        // 获取有效子节点并准备数据
        let validChildren = getValidChildren(from: node)
        guard !validChildren.isEmpty else {
            let rectangle = createLeafRectangle(node: node, rect: rect, level: level)
            rectangles.append(rectangle)
            return rectangles
        }

        // 规范化子节点数据
        let normalizedItems = normalizeChildrenData(
            validChildren, totalArea: rect.width * rect.height)

        // 执行Squarified分割
        let childRectangles = squarify(items: normalizedItems, rect: rect, level: level + 1)
        rectangles.append(contentsOf: childRectangles)

        return rectangles
    }

    /**
     * Squarify算法主体
     * 使用贪心策略优化矩形纵横比
     */
    private func squarify(items: [NormalizedItem], rect: CGRect, level: Int) -> [TreeMapRectangle] {
        guard !items.isEmpty else { return [] }

        var rectangles: [TreeMapRectangle] = []
        var remainingItems = items
        var currentRect = rect

        while !remainingItems.isEmpty {
            // 选择最佳的一行/列进行布局
            let (rowItems, restItems) = selectOptimalRow(from: remainingItems, in: currentRect)

            // 为这一行/列生成矩形
            let (rowRectangles, newRect) = layoutRow(items: rowItems, in: currentRect, level: level)
            rectangles.append(contentsOf: rowRectangles)

            // 更新剩余区域和项目
            remainingItems = restItems
            currentRect = newRect

            // 安全检查：避免无限循环
            if currentRect.width < minRectSize || currentRect.height < minRectSize {
                break
            }
        }

        return rectangles
    }

    /**
     * 选择最佳的一行进行布局
     * Linus式修复：遍历所有候选，取全局最优，消除贪心过早退出
     */
    private func selectOptimalRow(from items: [NormalizedItem], in rect: CGRect) -> (
        [NormalizedItem], [NormalizedItem]
    ) {
        guard !items.isEmpty else { return ([], []) }

        var bestRow: [NormalizedItem] = [items[0]]
        var bestAspectRatio = calculateWorstAspectRatio(items: [items[0]], in: rect)

        // Linus式修复：遍历所有可能的组合，取全局最优，而不是贪心早退
        for i in 1..<items.count {
            let candidateRow = Array(items[0...i])
            let aspectRatio = calculateWorstAspectRatio(items: candidateRow, in: rect)

            if aspectRatio < bestAspectRatio {
                bestRow = candidateRow
                bestAspectRatio = aspectRatio
                // 删除break，继续遍历所有候选
            }
        }

        let remainingItems = Array(items[bestRow.count...])
        return (bestRow, remainingItems)
    }

    /**
     * 为一行项目生成矩形布局
     * Linus式修复：最后一个矩形用剩余空间强制填满，消除精度问题和浮点误差累积
     */
    private func layoutRow(items: [NormalizedItem], in rect: CGRect, level: Int) -> (
        [TreeMapRectangle], CGRect
    ) {
        guard !items.isEmpty else { return ([], rect) }

        var rectangles: [TreeMapRectangle] = []
        let totalArea = items.reduce(0) { $0 + $1.normalizedSize }

        // 选择分割方向（较短的边）
        let isHorizontalSplit = rect.width <= rect.height

        if isHorizontalSplit {
            // 水平分割：沿y轴排列
            let stripHeight = totalArea / rect.width
            let actualHeight = min(stripHeight, rect.height)

            var currentX = rect.minX
            for (index, item) in items.enumerated() {
                let width: CGFloat
                if index == items.count - 1 {
                    // Linus式修复：最后一个用剩余空间，消除累积误差
                    width = rect.maxX - currentX
                } else {
                    width = item.normalizedSize / actualHeight
                }

                let itemRect = CGRect(x: currentX, y: rect.minY, width: width, height: actualHeight)

                // 递归处理子节点
                let childRectangles = squarifiedTreemap(for: item.node, in: itemRect, level: level)
                rectangles.append(contentsOf: childRectangles)

                currentX += width
            }

            // 返回剩余区域
            let remainingRect = CGRect(
                x: rect.minX,
                y: rect.minY + actualHeight,
                width: rect.width,
                height: rect.height - actualHeight
            )
            return (rectangles, remainingRect)

        } else {
            // 垂直分割：沿x轴排列
            let stripWidth = totalArea / rect.height
            let actualWidth = min(stripWidth, rect.width)

            var currentY = rect.minY
            for (index, item) in items.enumerated() {
                let height: CGFloat
                if index == items.count - 1 {
                    // Linus式修复：最后一个用剩余空间，消除累积误差
                    height = rect.maxY - currentY
                } else {
                    height = item.normalizedSize / actualWidth
                }

                let itemRect = CGRect(x: rect.minX, y: currentY, width: actualWidth, height: height)

                // 递归处理子节点
                let childRectangles = squarifiedTreemap(for: item.node, in: itemRect, level: level)
                rectangles.append(contentsOf: childRectangles)

                currentY += height
            }

            // 返回剩余区域
            let remainingRect = CGRect(
                x: rect.minX + actualWidth,
                y: rect.minY,
                width: rect.width - actualWidth,
                height: rect.height
            )
            return (rectangles, remainingRect)
        }
    }

    // MARK: - Helper Functions
    /**
     * 计算一组项目的最差纵横比
     * 用于优化布局质量
     */
    private func calculateWorstAspectRatio(items: [NormalizedItem], in rect: CGRect) -> CGFloat {
        guard !items.isEmpty else { return CGFloat.infinity }

        let totalArea = items.reduce(0) { $0 + $1.normalizedSize }
        let isHorizontalSplit = rect.width <= rect.height

        var worstRatio: CGFloat = 0

        if isHorizontalSplit {
            let stripHeight = totalArea / rect.width
            for item in items {
                let width = item.normalizedSize / stripHeight
                let aspectRatio = max(width / stripHeight, stripHeight / width)
                worstRatio = max(worstRatio, aspectRatio)
            }
        } else {
            let stripWidth = totalArea / rect.height
            for item in items {
                let height = item.normalizedSize / stripWidth
                let aspectRatio = max(stripWidth / height, height / stripWidth)
                worstRatio = max(worstRatio, aspectRatio)
            }
        }

        return worstRatio
    }

    /**
     * 规范化子节点数据
     * 将大小转换为面积单位
     */
    private func normalizeChildrenData(_ children: [TreeNode], totalArea: CGFloat)
        -> [NormalizedItem]
    {
        let totalSize = children.reduce(0) { $0 + $1.totalSize }
        guard totalSize > 0 else { return [] }

        return children.map { child in
            let proportion = CGFloat(child.totalSize) / CGFloat(totalSize)
            let normalizedSize = proportion * totalArea
            return NormalizedItem(node: child, normalizedSize: normalizedSize)
        }
    }

    /**
     * 获取有效的子节点
     * 过滤掉太小的项目
     */
    private func getValidChildren(from node: TreeNode) -> [TreeNode] {
        let totalSize = node.children.reduce(0) { $0 + $1.totalSize }
        guard totalSize > 0 else { return [] }

        return node.children
            .filter { child in
                let proportion = Double(child.totalSize) / Double(totalSize)
                return proportion > minSizeThreshold
            }
            .sorted { $0.totalSize > $1.totalSize }
    }

    /**
     * 判断是否应该终止递归
     * Linus式修复：消除节点消失问题，小节点也要画叶子而不是丢掉
     */
    private func shouldTerminate(rect: CGRect, level: Int, node: TreeNode) -> Bool {
        return rect.width < minRectSize || rect.height < minRectSize || level >= maxDepth
            || node.children.isEmpty || getValidChildren(from: node).isEmpty  // 只有没有有效子节点时才终止
    }

    /**
     * 创建叶子节点矩形
     * Linus式修复：使用全局最大值进行颜色归一化，确保颜色范围全局一致
     */
    private func createLeafRectangle(node: TreeNode, rect: CGRect, level: Int) -> TreeMapRectangle {
        return TreeMapRectangle(
            node: node,
            rect: rect,
            color: colorSchemeManager.adjustedColor(for: node, maxSize: globalMaxSize),
            level: level
        )
    }

    /**
     * 查找全局最大节点大小
     * Linus式修复：从根节点开始遍历，获取全局最大值而不是局部最大值
     */
    private func findGlobalMaxSize(in node: TreeNode) -> Int64 {
        var maxSize = node.totalSize

        func traverse(_ current: TreeNode) {
            maxSize = max(maxSize, current.totalSize)
            for child in current.children {
                traverse(child)
            }
        }

        // 从根节点开始遍历
        let root = findRoot(of: node)
        traverse(root)
        return maxSize
    }

    /**
     * 查找根节点
     */
    private func findRoot(of node: TreeNode) -> TreeNode {
        var current = node
        while let parent = current.parent {
            current = parent
        }
        return current
    }
}

// MARK: NormalizedItem - 规范化数据结构
/// 规范化的项目数据
/// 用于Squarified算法的中间计算
///
/// 将文件大小转换为屏幕面积单位，便于布局计算
private struct NormalizedItem {
    let node: TreeNode
    let normalizedSize: CGFloat
}

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
    @Published var totalSize: Int64 = 0
    @Published var rootNode: TreeNode?
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?
    private var estimatedTotalFiles: Int = 1000  // 用于进度估算

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
            .volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
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
            let contents = try fileManager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            estimatedTotalFiles = max(contents.count * 10, 1000)  // 简单估算
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
                    currentPath = item.path.path

                    // 更新进度
                    if filesScanned % 50 == 0 {
                        scanProgress = min(0.95, Double(filesScanned) / Double(estimatedTotalFiles))
                    }

                    // 递归扫描子目录
                    if item.isDirectory {
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

// MARK: - 工具模块
// MARK: FileSystemError - 错误类型定义
/// 文件系统操作相关的错误类型
/// 提供本地化的错误信息
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

// MARK: Array+Chunked - 数组分块扩展
/// 为Array添加chunked方法，用于将大数组分割成小批次处理
/// 这样可以优化内存使用，避免一次性处理太多数据
///
/// 使用场景：
/// - 批量文件处理
/// - 内存优化
/// - 流式数据处理
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
