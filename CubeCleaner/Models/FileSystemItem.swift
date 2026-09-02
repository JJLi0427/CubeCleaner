// FileSystemItem.swift — 文件系统项目数据模型

import Foundation

/// 文件系统项目的标准化数据结构。
/// 仅保留扫描/布局/展示所需字段（name/path/size/isDirectory），不存 UUID/时间戳。
struct FileSystemItem: Codable, Hashable {
    let name: String
    let path: URL
    let size: Int64
    let isDirectory: Bool

    /// 文件扩展名（小写）
    var fileExtension: String {
        path.pathExtension.lowercased()
    }
}
