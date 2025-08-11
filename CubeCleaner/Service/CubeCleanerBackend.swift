import Foundation
import Combine
import SwiftUI

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
    
    private func scanRecursively(node: TreeNode, currentDepth: Int) async {
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
                        await scanRecursively(node: childNode, currentDepth: currentDepth + 1)
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
