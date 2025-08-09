//
//  FileSystemError.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation

/// 文件系统相关错误
enum FileSystemError: LocalizedError, Equatable {
    case accessDenied(String)
    case invalidPath(String)
    case fileNotFound(String)
    case directoryNotFound(String)
    case permissionDenied(String)
    case diskSpaceInsufficient
    case maxDepthExceeded
    case scanCancelled
    case networkError(String)
    case unknownError(String)
    
    // MARK: - LocalizedError
    
    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "访问被拒绝：\(path)"
        case .invalidPath(let path):
            return "无效路径：\(path)"
        case .fileNotFound(let path):
            return "文件未找到：\(path)"
        case .directoryNotFound(let path):
            return "目录未找到：\(path)"
        case .permissionDenied(let path):
            return "权限不足：\(path)"
        case .diskSpaceInsufficient:
            return "磁盘空间不足"
        case .maxDepthExceeded:
            return "超过最大扫描深度"
        case .scanCancelled:
            return "扫描已取消"
        case .networkError(let message):
            return "网络错误：\(message)"
        case .unknownError(let message):
            return "未知错误：\(message)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .accessDenied:
            return "应用程序没有访问该路径的权限"
        case .invalidPath:
            return "指定的路径格式不正确或不存在"
        case .fileNotFound:
            return "指定的文件不存在或已被删除"
        case .directoryNotFound:
            return "指定的目录不存在或已被删除"
        case .permissionDenied:
            return "当前用户没有足够的权限执行此操作"
        case .diskSpaceInsufficient:
            return "磁盘剩余空间不足以完成操作"
        case .maxDepthExceeded:
            return "目录层级过深，为防止无限递归已停止扫描"
        case .scanCancelled:
            return "用户主动取消了扫描操作"
        case .networkError:
            return "网络连接出现问题"
        case .unknownError:
            return "发生了未预期的错误"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accessDenied, .permissionDenied:
            return "请在系统偏好设置 > 安全性与隐私 > 隐私 > 完全磁盘访问权限中添加此应用"
        case .invalidPath, .fileNotFound, .directoryNotFound:
            return "请检查路径是否正确，或选择其他有效的路径"
        case .diskSpaceInsufficient:
            return "请清理磁盘空间后重试"
        case .maxDepthExceeded:
            return "请选择层级较浅的目录进行扫描"
        case .scanCancelled:
            return "如需扫描，请重新开始扫描操作"
        case .networkError:
            return "请检查网络连接后重试"
        case .unknownError:
            return "请重试操作，如问题持续存在请联系技术支持"
        }
    }
    
    // MARK: - Error Classification
    
    /// 是否为权限相关错误
    var isPermissionError: Bool {
        switch self {
        case .accessDenied, .permissionDenied:
            return true
        default:
            return false
        }
    }
    
    /// 是否为路径相关错误
    var isPathError: Bool {
        switch self {
        case .invalidPath, .fileNotFound, .directoryNotFound:
            return true
        default:
            return false
        }
    }
    
    /// 是否为系统资源错误
    var isSystemResourceError: Bool {
        switch self {
        case .diskSpaceInsufficient, .maxDepthExceeded:
            return true
        default:
            return false
        }
    }
    
    /// 是否为用户操作错误
    var isUserActionError: Bool {
        switch self {
        case .scanCancelled:
            return true
        default:
            return false
        }
    }
    
    /// 错误严重程度
    var severity: ErrorSeverity {
        switch self {
        case .scanCancelled:
            return .info
        case .fileNotFound, .directoryNotFound:
            return .warning
        case .accessDenied, .permissionDenied, .invalidPath:
            return .error
        case .diskSpaceInsufficient, .maxDepthExceeded, .networkError, .unknownError:
            return .critical
        }
    }
    
    /// 获取用户友好的错误消息
    var userFriendlyMessage: String {
        switch self {
        case .accessDenied, .permissionDenied:
            return "需要访问权限才能扫描该位置"
        case .invalidPath, .fileNotFound, .directoryNotFound:
            return "无法找到指定的文件或文件夹"
        case .diskSpaceInsufficient:
            return "磁盘空间不足"
        case .maxDepthExceeded:
            return "文件夹层级太深，无法完全扫描"
        case .scanCancelled:
            return "扫描已取消"
        case .networkError:
            return "网络连接问题"
        case .unknownError:
            return "发生未知错误"
        }
    }
}

// MARK: - Supporting Types

/// 错误严重程度
enum ErrorSeverity: String, CaseIterable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
    
    var description: String {
        switch self {
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        case .critical: return "严重"
        }
    }
    
    var iconName: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }
    
    var colorName: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        case .critical: return "purple"
        }
    }
}

// MARK: - Error Extensions

extension FileSystemError {
    /// 创建访问被拒绝错误
    /// - Parameter url: 被拒绝访问的 URL
    /// - Returns: 访问被拒绝错误
    static func accessDenied(for url: URL) -> FileSystemError {
        return .accessDenied(url.path)
    }
    
    /// 创建文件未找到错误
    /// - Parameter url: 未找到的文件 URL
    /// - Returns: 文件未找到错误
    static func fileNotFound(for url: URL) -> FileSystemError {
        return .fileNotFound(url.path)
    }
    
    /// 创建目录未找到错误
    /// - Parameter url: 未找到的目录 URL
    /// - Returns: 目录未找到错误
    static func directoryNotFound(for url: URL) -> FileSystemError {
        return .directoryNotFound(url.path)
    }
    
    /// 从系统错误创建文件系统错误
    /// - Parameter error: 系统错误
    /// - Returns: 对应的文件系统错误
    static func from(systemError error: Error) -> FileSystemError {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSFileReadNoPermissionError:
            return .permissionDenied(nsError.localizedDescription)
        case NSFileNoSuchFileError:
            return .fileNotFound(nsError.localizedDescription)
        case NSFileReadNoSuchFileError:
            return .directoryNotFound(nsError.localizedDescription)
        case NSVolumeReadOnlyError:
            return .permissionDenied("卷为只读")
        default:
            return .unknownError(nsError.localizedDescription)
        }
    }
}
