//
//  FileSystemItem.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation
import UniformTypeIdentifiers

/// 文件系统项目的基础模型
/// 表示文件系统中的文件或文件夹，包含基本属性和层次结构信息
@Observable
class FileSystemItem: Identifiable, Hashable {
    // MARK: - Properties
    
    /// 唯一标识符
    let id = UUID()
    
    /// 文件或文件夹名称
    let name: String
    
    /// 完整文件路径
    let path: URL
    
    /// 文件大小（字节）
    let size: Int64
    
    /// 是否为目录
    let isDirectory: Bool
    
    /// 文件类型
    let fileType: FileType
    
    /// 创建日期
    let creationDate: Date?
    
    /// 修改日期
    let modificationDate: Date?
    
    /// 文件权限
    let permissions: FilePermissions
    
    /// 父级目录（如果存在）
    weak var parent: FileSystemItem?
    
    /// 子项目集合（仅目录有效）
    private(set) var children: [FileSystemItem] = []
    
    /// 计算属性：深度（从根目录开始）
    var depth: Int {
        var currentDepth = 0
        var current = parent
        while current != nil {
            currentDepth += 1
            current = current?.parent
        }
        return currentDepth
    }
    
    /// 计算属性：总大小（包含所有子项）
    var totalSize: Int64 {
        if isDirectory {
            return size + children.reduce(0) { $0 + $1.totalSize }
        }
        return size
    }
    
    /// 计算属性：子文件数量
    var fileCount: Int {
        if isDirectory {
            return children.filter { !$0.isDirectory }.count +
                   children.filter { $0.isDirectory }.reduce(0) { $0 + $1.fileCount }
        }
        return 1
    }
    
    /// 计算属性：子文件夹数量
    var directoryCount: Int {
        if isDirectory {
            return children.filter { $0.isDirectory }.count +
                   children.filter { $0.isDirectory }.reduce(0) { $0 + $1.directoryCount }
        }
        return 0
    }
    
    // MARK: - Initialization
    
    /// 初始化文件系统项目
    /// - Parameters:
    ///   - name: 文件或文件夹名称
    ///   - path: 完整文件路径
    ///   - size: 文件大小
    ///   - isDirectory: 是否为目录
    ///   - fileType: 文件类型
    ///   - creationDate: 创建日期
    ///   - modificationDate: 修改日期
    ///   - permissions: 文件权限
    init(name: String,
         path: URL,
         size: Int64,
         isDirectory: Bool,
         fileType: FileType,
         creationDate: Date? = nil,
         modificationDate: Date? = nil,
         permissions: FilePermissions = .readable) {
        
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.fileType = fileType
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.permissions = permissions
    }
    
    /// 从 URL 创建文件系统项目
    /// - Parameter url: 文件或文件夹的 URL
    /// - Returns: 文件系统项目实例，如果创建失败返回 nil
    static func from(url: URL) -> FileSystemItem? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .nameKey,
                .fileSizeKey,
                .isDirectoryKey,
                .contentTypeKey,
                .creationDateKey,
                .contentModificationDateKey
            ])
            
            guard let name = resourceValues.name else { return nil }
            let size = Int64(resourceValues.fileSize ?? 0)
            let isDirectory = resourceValues.isDirectory ?? false
            let creationDate = resourceValues.creationDate
            let modificationDate = resourceValues.contentModificationDate
            
            // 确定文件类型
            let fileType = FileType.from(url: url, contentType: resourceValues.contentType)
            
            // 检查文件权限
            let permissions = FilePermissions.from(url: url)
            
            return FileSystemItem(
                name: name,
                path: url,
                size: size,
                isDirectory: isDirectory,
                fileType: fileType,
                creationDate: creationDate,
                modificationDate: modificationDate,
                permissions: permissions
            )
        } catch {
            print("Error creating FileSystemItem from URL: \(error)")
            return nil
        }
    }
    
    // MARK: - Tree Management
    
    /// 添加子项目
    /// - Parameter child: 要添加的子项目
    func addChild(_ child: FileSystemItem) {
        guard isDirectory else { return }
        child.parent = self
        children.append(child)
    }
    
    /// 移除子项目
    /// - Parameter child: 要移除的子项目
    func removeChild(_ child: FileSystemItem) {
        children.removeAll { $0.id == child.id }
        child.parent = nil
    }
    
    /// 获取指定路径的子项目
    /// - Parameter relativePath: 相对路径
    /// - Returns: 找到的文件系统项目，如果不存在返回 nil
    func child(at relativePath: String) -> FileSystemItem? {
        let components = relativePath.split(separator: "/")
        guard !components.isEmpty else { return self }
        
        let firstComponent = String(components[0])
        guard let child = children.first(where: { $0.name == firstComponent }) else {
            return nil
        }
        
        if components.count == 1 {
            return child
        } else {
            let remainingPath = components.dropFirst().joined(separator: "/")
            return child.child(at: remainingPath)
        }
    }
    
    // MARK: - Utility Methods
    
    /// 格式化文件大小为人类可读的字符串
    /// - Parameter includeBytes: 是否包含字节单位
    /// - Returns: 格式化的大小字符串
    func formattedSize(includeBytes: Bool = false) -> String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// 获取文件扩展名
    var fileExtension: String {
        return path.pathExtension.lowercased()
    }
    
    /// 获取相对于指定父目录的路径
    /// - Parameter ancestor: 祖先目录
    /// - Returns: 相对路径字符串
    func relativePath(from ancestor: FileSystemItem) -> String? {
        var currentItem: FileSystemItem? = self
        var pathComponents: [String] = []
        
        while let current = currentItem, current.id != ancestor.id {
            pathComponents.insert(current.name, at: 0)
            currentItem = current.parent
        }
        
        guard currentItem?.id == ancestor.id else {
            return nil // 不是祖先关系
        }
        
        return pathComponents.joined(separator: "/")
    }
    
    // MARK: - Hashable & Equatable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Supporting Types

/// 文件权限枚举
enum FilePermissions: String, CaseIterable {
    case readable = "readable"
    case writable = "writable"
    case executable = "executable"
    case readWrite = "readWrite"
    case full = "full"
    case none = "none"
    
    /// 从 URL 获取文件权限
    /// - Parameter url: 文件 URL
    /// - Returns: 文件权限
    static func from(url: URL) -> FilePermissions {
        let fileManager = FileManager.default
        
        let isReadable = fileManager.isReadableFile(atPath: url.path)
        let isWritable = fileManager.isWritableFile(atPath: url.path)
        let isExecutable = fileManager.isExecutableFile(atPath: url.path)
        
        switch (isReadable, isWritable, isExecutable) {
        case (true, true, true):
            return .full
        case (true, true, false):
            return .readWrite
        case (true, false, true):
            return .executable
        case (true, false, false):
            return .readable
        case (false, true, false):
            return .writable
        default:
            return .none
        }
    }
    
    /// 权限描述
    var description: String {
        switch self {
        case .readable: return "只读"
        case .writable: return "只写"
        case .executable: return "可执行"
        case .readWrite: return "读写"
        case .full: return "完全权限"
        case .none: return "无权限"
        }
    }
}
