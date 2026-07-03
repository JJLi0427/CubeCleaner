// FileSystemItem.swift — 文件系统项目数据模型

import Foundation

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
