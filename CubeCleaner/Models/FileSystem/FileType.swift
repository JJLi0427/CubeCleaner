//
//  FileType.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation
import UniformTypeIdentifiers

/// 文件类型枚举
/// 用于分类和标识不同类型的文件，支持图标显示和颜色编码
enum FileType: String, CaseIterable, Codable {
    // MARK: - Document Types
    case document = "document"
    case text = "text"
    case pdf = "pdf"
    case spreadsheet = "spreadsheet"
    case presentation = "presentation"
    
    // MARK: - Media Types
    case image = "image"
    case video = "video"
    case audio = "audio"
    
    // MARK: - Code Types
    case code = "code"
    case swift = "swift"
    case javascript = "javascript"
    case python = "python"
    case html = "html"
    case css = "css"
    case json = "json"
    case xml = "xml"
    
    // MARK: - Archive Types
    case archive = "archive"
    case zip = "zip"
    case dmg = "dmg"
    
    // MARK: - System Types
    case application = "application"
    case system = "system"
    case executable = "executable"
    
    // MARK: - Special Types
    case directory = "directory"
    case unknown = "unknown"
    case symlink = "symlink"
    
    // MARK: - Type Detection
    
    /// 从 URL 和内容类型推断文件类型
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - contentType: UTType 内容类型
    /// - Returns: 推断的文件类型
    static func from(url: URL, contentType: UTType?) -> FileType {
        let fileExtension = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent.lowercased()
        
        // 检查是否为目录
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return .directory
            }
        }
        
        // 检查是否为符号链接
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                return .symlink
            }
        } catch {
            // 忽略错误，继续检测
        }
        
        // 基于内容类型检测
        if let contentType = contentType {
            if contentType.conforms(to: .image) {
                return .image
            } else if contentType.conforms(to: .video) {
                return .video
            } else if contentType.conforms(to: .audio) {
                return .audio
            } else if contentType.conforms(to: .pdf) {
                return .pdf
            } else if contentType.conforms(to: .application) {
                return .application
            } else if contentType.conforms(to: .executable) {
                return .executable
            }
        }
        
        // 基于文件扩展名检测
        return from(extension: fileExtension)
    }
    
    /// 从文件扩展名推断文件类型
    /// - Parameter extension: 文件扩展名（不含点）
    /// - Returns: 推断的文件类型
    static func from(extension: String) -> FileType {
        let ext = `extension`.lowercased()
        
        switch ext {
        // Swift 开发
        case "swift", "swiftui":
            return .swift
            
        // Web 开发
        case "js", "jsx", "ts", "tsx", "mjs":
            return .javascript
        case "html", "htm", "xhtml":
            return .html
        case "css", "scss", "sass", "less":
            return .css
            
        // 编程语言
        case "py", "pyw", "pyc":
            return .python
        case "json":
            return .json
        case "xml", "plist", "xib", "storyboard":
            return .xml
        case "c", "cpp", "cc", "cxx", "h", "hpp", "m", "mm", "java", "kt", "rs", "go", "rb", "php":
            return .code
            
        // 文档类型
        case "txt", "md", "readme", "rtf":
            return .text
        case "pdf":
            return .pdf
        case "doc", "docx", "odt", "pages":
            return .document
        case "xls", "xlsx", "csv", "numbers":
            return .spreadsheet
        case "ppt", "pptx", "key", "odp":
            return .presentation
            
        // 媒体文件
        case "jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "tiff", "ico", "heic", "heif":
            return .image
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v":
            return .video
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma":
            return .audio
            
        // 压缩文件
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return .archive
        case "dmg", "pkg", "app":
            return .dmg
            
        // 应用程序
        case "app", "exe", "msi", "deb", "rpm":
            return .application
            
        // 系统文件
        case "sys", "dll", "so", "dylib", "framework":
            return .system
            
        default:
            return .unknown
        }
    }
    
    // MARK: - Properties
    
    /// 文件类型的显示名称
    var displayName: String {
        switch self {
        case .document: return "文档"
        case .text: return "文本文件"
        case .pdf: return "PDF 文档"
        case .spreadsheet: return "电子表格"
        case .presentation: return "演示文稿"
        case .image: return "图像文件"
        case .video: return "视频文件"
        case .audio: return "音频文件"
        case .code: return "代码文件"
        case .swift: return "Swift 代码"
        case .javascript: return "JavaScript 代码"
        case .python: return "Python 代码"
        case .html: return "HTML 文件"
        case .css: return "CSS 样式表"
        case .json: return "JSON 数据"
        case .xml: return "XML 文件"
        case .archive: return "压缩文件"
        case .zip: return "ZIP 压缩包"
        case .dmg: return "磁盘镜像"
        case .application: return "应用程序"
        case .system: return "系统文件"
        case .executable: return "可执行文件"
        case .directory: return "文件夹"
        case .unknown: return "未知文件"
        case .symlink: return "符号链接"
        }
    }
    
    /// 文件类型图标名称（SF Symbols）
    var iconName: String {
        switch self {
        case .document: return "doc.text"
        case .text: return "doc.plaintext"
        case .pdf: return "doc.pdf"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "music.note"
        case .code, .swift, .javascript, .python, .html, .css, .json, .xml:
            return "chevron.left.forwardslash.chevron.right"
        case .archive, .zip: return "archivebox"
        case .dmg: return "externaldrive"
        case .application: return "app"
        case .system: return "gear"
        case .executable: return "terminal"
        case .directory: return "folder"
        case .symlink: return "link"
        case .unknown: return "questionmark.diamond"
        }
    }
    
    /// 文件类型的颜色（十六进制）
    var colorHex: String {
        switch self {
        case .document, .text, .pdf: return "#4A90E2"
        case .spreadsheet: return "#50C878"
        case .presentation: return "#FF6B35"
        case .image: return "#E74C3C"
        case .video: return "#9B59B6"
        case .audio: return "#F39C12"
        case .swift: return "#FA7343"
        case .javascript: return "#F7DF1E"
        case .python: return "#3776AB"
        case .html: return "#E34F26"
        case .css: return "#1572B6"
        case .json: return "#000000"
        case .xml: return "#FF6600"
        case .code: return "#2ECC71"
        case .archive, .zip: return "#95A5A6"
        case .dmg: return "#34495E"
        case .application: return "#3498DB"
        case .system: return "#7F8C8D"
        case .executable: return "#2C3E50"
        case .directory: return "#3498DB"
        case .symlink: return "#9B59B6"
        case .unknown: return "#BDC3C7"
        }
    }
    
    /// 是否为媒体文件
    var isMedia: Bool {
        return [.image, .video, .audio].contains(self)
    }
    
    /// 是否为代码文件
    var isCode: Bool {
        return [.code, .swift, .javascript, .python, .html, .css, .json, .xml].contains(self)
    }
    
    /// 是否为文档文件
    var isDocument: Bool {
        return [.document, .text, .pdf, .spreadsheet, .presentation].contains(self)
    }
    
    /// 是否为压缩文件
    var isArchive: Bool {
        return [.archive, .zip, .dmg].contains(self)
    }
    
    /// 是否为可执行文件
    var isExecutable: Bool {
        return [.application, .executable].contains(self)
    }
    
    // MARK: - Category Grouping
    
    /// 获取文件类型分组
    var category: FileCategory {
        if isDocument { return .documents }
        if isMedia { return .media }
        if isCode { return .code }
        if isArchive { return .archives }
        if isExecutable { return .applications }
        if self == .directory { return .directories }
        return .others
    }
}

/// 文件分类枚举
enum FileCategory: String, CaseIterable {
    case documents = "documents"
    case media = "media"
    case code = "code"
    case archives = "archives"
    case applications = "applications"
    case directories = "directories"
    case others = "others"
    
    var displayName: String {
        switch self {
        case .documents: return "文档"
        case .media: return "媒体"
        case .code: return "代码"
        case .archives: return "压缩包"
        case .applications: return "应用程序"
        case .directories: return "文件夹"
        case .others: return "其他"
        }
    }
    
    var iconName: String {
        switch self {
        case .documents: return "doc.text"
        case .media: return "photo.on.rectangle.angled"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archives: return "archivebox"
        case .applications: return "app.badge"
        case .directories: return "folder.badge.plus"
        case .others: return "ellipsis.circle"
        }
    }
}
