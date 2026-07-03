// FileType.swift — 文件类型枚举

import Foundation

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
