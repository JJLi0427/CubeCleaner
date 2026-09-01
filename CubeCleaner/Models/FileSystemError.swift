// FileSystemError.swift — 文件系统错误类型

import Foundation

// MARK: - 错误类型定义
/// 文件系统操作相关的错误类型
enum FileSystemError: LocalizedError {
    case accessDenied
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "无法访问所选文件夹，请检查权限设置"
        case .invalidPath:
            return "无效的文件路径"
        }
    }
}
