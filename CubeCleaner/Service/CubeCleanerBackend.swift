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
 * │   ├── BinaryTreeMapCalculator - Binary Tree TreeMap布局计算器
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

    /// 是否为聚合的虚拟"其他"节点
    private(set) var isAggregated: Bool = false

    /// 标记为聚合节点
    func markAsAggregated() {
        isAggregated = true
    }

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

    /// 高饱和调色板（v0.3）— 固定 RGB，不做亮/暗分别调色
    private let fileTypeColors: [FileType: Color] = [
        .document: Color(red: 0.039, green: 0.518, blue: 1.0),     // #0A84FF
        .image: Color(red: 0.188, green: 0.820, blue: 0.345),      // #30D158
        .video: Color(red: 1.0, green: 0.271, blue: 0.227),        // #FF453A
        .audio: Color(red: 0.749, green: 0.353, blue: 0.949),      // #BF5AF2
        .archive: Color(red: 1.0, green: 0.624, blue: 0.039),      // #FF9F0A
        .application: Color(red: 0.392, green: 0.824, blue: 1.0),  // #64D2FF
        .system: Color(red: 1.0, green: 0.839, blue: 0.039),       // #FFD60A
        .other: Color(red: 1.0, green: 0.216, blue: 0.373),        // #FF375F
    ]

    /// 文件夹专用颜色（高饱和深青）
    private let directoryColor: Color = Color(red: 0.251, green: 0.784, blue: 0.878)  // #40C8E0

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

    /// 类型占比条目（供统计条比例条与图例侧栏共用）
    struct TypeBreakdownEntry: Identifiable {
        var id: FileType { type }
        let type: FileType
        let size: Int64
        let color: Color
        var ratio: CGFloat {      // size / total；total=0 时外部不渲染
            total > 0 ? CGFloat(size) / CGFloat(total) : 0
        }
        let total: Int64
    }

    /// 聚合 node 子树所有叶子文件，按 FileType 累加 item.size。
    /// 文件夹不计入（避免与子文件重复）。返回 8 类型（含 size=0），按 size 降序。
    func typeBreakdown(for node: TreeNode) -> [TypeBreakdownEntry] {
        var sizes: [FileType: Int64] = [:]
        for type in FileType.allCases { sizes[type] = 0 }

        func traverse(_ current: TreeNode) {
            if current.item.isDirectory {
                for child in current.children { traverse(child) }
            } else {
                let ft = FileType.from(extension: current.item.fileExtension)
                sizes[ft, default: 0] += current.item.size
            }
        }
        traverse(node)

        let total = sizes.values.reduce(Int64(0), +)
        return FileType.allCases
            .map { TypeBreakdownEntry(type: $0, size: sizes[$0] ?? 0, color: color(for: $0), total: total) }
            .sorted { $0.size > $1.size }
    }

    /// 统计 node 子树的叶子文件数（非目录）
    func fileCountInSubtree(_ node: TreeNode) -> Int {
        if node.item.isDirectory {
            return node.children.reduce(0) { $0 + fileCountInSubtree($1) }
        } else {
            return 1
        }
    }

    /// 统计 node 子树的目录数（含 node 自身若为目录）
    func folderCountInSubtree(_ node: TreeNode) -> Int {
        let selfCount = node.item.isDirectory ? 1 : 0
        return selfCount + node.children.reduce(0) { $0 + folderCountInSubtree($1) }
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
    let isAggregated: Bool  // 是否为聚合的"其他"块

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

// MARK: - Binary Tree TreeMap 布局计算器
/// Binary Tree TreeMap算法实现
/// Linus式设计原则：消除特殊情况，最简数据结构，零废话
///
/// 核心思想：
/// 1. 把复杂的Squarified算法扔掉 - 它是过度设计的垃圾
/// 2. 用Binary Tree简单二分法：大的一半，小的一半，完事
/// 3. 没有特殊情况，没有复杂计算，就是递归二分
/// 4. 数据结构决定算法 - TreeMap就是个Binary Tree的可视化
class BinaryTreeMapCalculator: ObservableObject {

    // MARK: - 核心常量 - 实用主义优先
    private let colorSchemeManager = ColorSchemeManager.shared
    private let minVisibleSize: CGFloat = 24  // 最小可见尺寸：24x24像素，用户能看清
    private let maxDepth: Int = 8  // 限制递归深度，避免过度分割
    private let minFileRatio: Double = 0.005  // 聚合阈值：小于总大小0.5%的文件归入"其他"块

    // MARK: - 全局状态 - 一个变量搞定颜色
    private var globalMaxSize: Int64 = 0

    // MARK: - 主入口 - 就这一个函数，其他都是实现细节
    /**
     * Binary Tree TreeMap主算法
     * 输入：节点和矩形 -> 输出：矩形列表
     * 没有花哨的东西，就是递归二分
     */
    func calculateLayout(for node: TreeNode, in rect: CGRect) -> [TreeMapRectangle] {
        // 太小就不画，实用主义
        if rect.width < minVisibleSize || rect.height < minVisibleSize {
            return []
        }

        // 设置全局最大值，用于颜色和阈值计算
        globalMaxSize = findMaxSize(from: node)

        // 入口为聚合"其他"块：用户双击钻取进来，需展开其内部小文件。
        // 普通目录走默认分支；聚合节点只有在作为钻取根时才展开。
        if node.isAggregated {
            return binaryTreeMap(node: node, rect: rect, depth: 0, expandAggregated: true)
        }

        // 开始递归
        return binaryTreeMap(node: node, rect: rect, depth: 0)
    }

    // MARK: - 核心算法 - Binary Tree递归分割
    /**
     * Binary Tree核心算法 - 重新设计版本
     *
     * Linus式设计原则：
     * 1. 消除虚拟节点 - 它们是过度设计的垃圾
     * 2. 直接处理节点数组 - 简单粗暴有效
     * 3. 没有特殊情况 - 递归到底
     */
    private func binaryTreeMap(node: TreeNode, rect: CGRect, depth: Int, expandAggregated: Bool = false) -> [TreeMapRectangle] {
        // 获取有效子节点
        let children = getValidChildren(of: node)

        // 递归终止：没有子节点就画叶子
        if children.isEmpty {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        // 太深了，直接展平所有子节点
        if depth >= maxDepth {
            return flattenChildren(children, in: rect, depth: depth)
        }

        // 聚合"其他"块：默认作为叶子矩形直接绘制，不参与递归二分。
        // 当它是用户双击钻取的根节点时(expandAggregated=true)，
        // 需展开其内部小文件供查看，越过此叶子逻辑继续递归。
        if node.isAggregated && !expandAggregated {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        // 只有一个子节点？直接递归
        if children.count == 1 {
            return binaryTreeMap(node: children[0], rect: rect, depth: depth + 1)
        }

        // 二分处理：直接分割节点数组，不需要虚拟节点
        return binaryPartition(children: children, rect: rect, depth: depth)
    }

    /**
     * 二分分割 - 不使用虚拟节点的简洁版本
     */
    private func binaryPartition(children: [TreeNode], rect: CGRect, depth: Int)
        -> [TreeMapRectangle]
    {
        guard children.count >= 2 else {
            // 应该不会到这里，但防御性编程
            return children.flatMap { binaryTreeMap(node: $0, rect: rect, depth: depth + 1) }
        }

        // 按大小排序
        let sortedChildren = children.sorted { $0.totalSize > $1.totalSize }

        // 找到最佳分割点 - 不一定是1个vs其他，而是平衡的分割
        let splitIndex = findBestSplitIndex(sortedChildren)
        let leftGroup = Array(sortedChildren[0..<splitIndex])
        let rightGroup = Array(sortedChildren[splitIndex...])

        // 计算分组大小比例
        let leftSize = leftGroup.reduce(0) { $0 + $1.totalSize }
        let rightSize = rightGroup.reduce(0) { $0 + $1.totalSize }
        let totalSize = leftSize + rightSize

        guard totalSize > 0 else { return [] }

        let leftRatio = CGFloat(leftSize) / CGFloat(totalSize)

        // 分割矩形
        let (leftRect, rightRect) = splitRect(
            rect: rect,
            ratio: leftRatio,
            isVertical: rect.width > rect.height
        )

        var result: [TreeMapRectangle] = []

        // 递归处理左侧组
        result.append(contentsOf: processGroup(leftGroup, in: leftRect, depth: depth + 1))

        // 递归处理右侧组
        result.append(contentsOf: processGroup(rightGroup, in: rightRect, depth: depth + 1))

        return result
    }

    /**
     * 处理节点组 - 不创建虚拟节点
     */
    private func processGroup(_ nodes: [TreeNode], in rect: CGRect, depth: Int)
        -> [TreeMapRectangle]
    {
        if nodes.count == 1 {
            return binaryTreeMap(node: nodes[0], rect: rect, depth: depth)
        } else {
            return binaryPartition(children: nodes, rect: rect, depth: depth)
        }
    }

    /**
     * 找到最佳分割索引 - 尽量平衡两组
     */
    private func findBestSplitIndex(_ sortedChildren: [TreeNode]) -> Int {
        guard sortedChildren.count > 1 else { return 1 }

        let totalSize = sortedChildren.reduce(0) { $0 + $1.totalSize }
        let targetSize = totalSize / 2

        var currentSize: Int64 = 0
        for (index, child) in sortedChildren.enumerated() {
            currentSize += child.totalSize
            if currentSize >= targetSize || index == sortedChildren.count - 1 {
                return max(1, index + 1)  // 至少分割出1个
            }
        }

        return sortedChildren.count / 2  // fallback
    }

    /**
     * 展平处理 - 当递归太深时，简单排列所有子节点
     * 修复：正确布局子节点，而不是重叠在同一位置
     */
    private func flattenChildren(_ children: [TreeNode], in rect: CGRect, depth: Int)
        -> [TreeMapRectangle]
    {
        guard !children.isEmpty else { return [] }

        // 如果只有一个子节点，占据整个区域
        if children.count == 1 {
            return [createLeafRectangle(node: children[0], rect: rect, depth: depth)]
        }

        // 按大小排序
        let sortedChildren = children.sorted { $0.totalSize > $1.totalSize }
        let totalSize = sortedChildren.reduce(0) { $0 + $1.totalSize }

        guard totalSize > 0 else { return [] }

        var result: [TreeMapRectangle] = []
        var currentRect = rect

        // 简单的线性布局
        let isVertical = rect.width > rect.height

        for (index, child) in sortedChildren.enumerated() {
            let ratio = CGFloat(child.totalSize) / CGFloat(totalSize)

            if index == sortedChildren.count - 1 {
                // 最后一个子节点占据剩余空间
                result.append(createLeafRectangle(node: child, rect: currentRect, depth: depth))
            } else {
                let childRect: CGRect
                if isVertical {
                    // 垂直分割
                    let width = currentRect.width * ratio
                    childRect = CGRect(
                        x: currentRect.minX,
                        y: currentRect.minY,
                        width: width,
                        height: currentRect.height
                    )
                    currentRect = CGRect(
                        x: currentRect.minX + width,
                        y: currentRect.minY,
                        width: currentRect.width - width,
                        height: currentRect.height
                    )
                } else {
                    // 水平分割
                    let height = currentRect.height * ratio
                    childRect = CGRect(
                        x: currentRect.minX,
                        y: currentRect.minY,
                        width: currentRect.width,
                        height: height
                    )
                    currentRect = CGRect(
                        x: currentRect.minX,
                        y: currentRect.minY + height,
                        width: currentRect.width,
                        height: currentRect.height - height
                    )
                }

                result.append(createLeafRectangle(node: child, rect: childRect, depth: depth))
            }
        }

        return result
    }

    // MARK: - 工具函数 - 简单直接，没有复杂逻辑

    /**
     * 分割矩形 - 永远二分，没有特殊情况
     */
    private func splitRect(rect: CGRect, ratio: CGFloat, isVertical: Bool) -> (CGRect, CGRect) {
        if isVertical {
            // 垂直分割
            let splitX = rect.minX + rect.width * ratio
            let left = CGRect(
                x: rect.minX, y: rect.minY, width: rect.width * ratio, height: rect.height)
            let right = CGRect(
                x: splitX, y: rect.minY, width: rect.width * (1 - ratio), height: rect.height)
            return (left, right)
        } else {
            // 水平分割
            let splitY = rect.minY + rect.height * ratio
            let top = CGRect(
                x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * ratio)
            let bottom = CGRect(
                x: rect.minX, y: splitY, width: rect.width, height: rect.height * (1 - ratio))
            return (top, bottom)
        }
    }

    /**
     * 获取有效子节点 - 聚合"其他"块策略
     *
     * 规则：
     * 1. 移除大小为0的节点
     * 2. 按大小降序排序
     * 3. 阈值 = 父目录总大小 × minFileRatio (0.5%)
     * 4. 保留所有 >= 阈值的子项
     * 5. 剩余子项聚合为一个虚拟"其他"节点（面积守恒，保留子项以支持双击钻取）
     * 6. 边界：若全部 < 阈值，不聚合，保留前 10 大，避免空图
     */
    private func getValidChildren(of parent: TreeNode) -> [TreeNode] {
        let nonZeroChildren = parent.children.filter { $0.totalSize > 0 }
        guard !nonZeroChildren.isEmpty else { return [] }

        // 子节点不多，直接返回
        if nonZeroChildren.count <= 5 {
            return nonZeroChildren
        }

        let sortedChildren = nonZeroChildren.sorted { $0.totalSize > $1.totalSize }
        let totalSize = sortedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        let threshold = Int64(Double(totalSize) * minFileRatio)

        // 分离保留项与待聚合项
        var kept: [TreeNode] = []
        var aggregatedChildren: [TreeNode] = []

        for child in sortedChildren {
            if child.totalSize >= threshold {
                kept.append(child)
            } else {
                aggregatedChildren.append(child)
            }
        }

        // 边界：若全部 < 阈值（即 kept 为空），保留前 10 大，不聚合
        if kept.isEmpty {
            return Array(sortedChildren.prefix(10))
        }

        // 没有可聚合的小文件，直接返回
        if aggregatedChildren.isEmpty {
            return kept
        }

        // 构造虚拟"其他"节点 - 把待聚合的子项挂为它的 children，
        // 这样双击该块可钻取进去看内部小文件。
        // 注意：isDirectory 保持 false，使 totalSize 走文件分支返回 item.size，
        // 保证面积守恒（若为 true 会叠加 children 总大小导致面积翻倍）。
        let aggregatedSize = aggregatedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        let otherItem = FileSystemItem(
            name: "其他 (\(aggregatedChildren.count) 项)",
            path: URL(fileURLWithPath: "/__aggregated__"),
            size: aggregatedSize,
            isDirectory: false,
            creationDate: Date(timeIntervalSince1970: 0),
            modificationDate: Date(timeIntervalSince1970: 0)
        )
        let otherNode = TreeNode(item: otherItem, parent: parent)
        otherNode.markAsAggregated()
        // 复用原有子节点（不改其 parent），仅挂到 otherNode.children 下，
        // 供钻取后布局使用；面包屑只需沿 otherNode.parent 上溯即可。
        for child in aggregatedChildren {
            otherNode.addChild(child)
        }

        return kept + [otherNode]
    }

    /**
     * 查找最大文件大小 - 简单遍历
     */
    private func findMaxSize(from node: TreeNode) -> Int64 {
        var maxSize = node.totalSize

        func traverse(_ current: TreeNode) {
            maxSize = max(maxSize, current.totalSize)
            current.children.forEach { traverse($0) }
        }

        traverse(node)
        return maxSize
    }

    /**
     * 创建叶子矩形 - 就是包装一下数据
     */
    private func createLeafRectangle(node: TreeNode, rect: CGRect, depth: Int, isAggregated: Bool = false) -> TreeMapRectangle {
        let color: Color
        if node.isAggregated {
            color = Color(.systemGray).opacity(0.5)
        } else {
            color = colorSchemeManager.adjustedColor(for: node, maxSize: globalMaxSize)
        }
        return TreeMapRectangle(
            node: node,
            rect: rect,
            color: color,
            level: depth,
            isAggregated: node.isAggregated
        )
    }
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
    @Published var folderCount: Int = 0
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
                    currentPath = item.path.path

                    // 更新进度
                    if filesScanned % 50 == 0 {
                        scanProgress = min(0.95, Double(filesScanned) / Double(estimatedTotalFiles))
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
