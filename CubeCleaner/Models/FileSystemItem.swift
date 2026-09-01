// FileSystemItem.swift — 文件系统项目数据模型

import Foundation

// MARK: - 数据模型模块
// MARK: FileSystemItem - 文件系统项目数据模型
/// 文件系统项目的标准化数据结构
/// 包含文件/文件夹的基本属性
///
/// 特性：
/// - Hashable: 支持集合操作
/// - 仅保留扫描/布局/展示所需字段（name/path/size/isDirectory），
///   不存 UUID/时间戳，避免百万级条目无意义的分配开销。
struct FileSystemItem: Codable, Hashable {
    let name: String
    let path: URL
    let size: Int64
    let isDirectory: Bool

    init(name: String, path: URL, size: Int64, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
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
