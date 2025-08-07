//
//  FileSystemItem.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import SwiftUI

// Enum to represent file types
enum FileType: String, Codable {
    case folder = "folder"
    case document = "document"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case archive = "archive"
    case application = "application"
    case system = "system"
    case other = "other"
    
    // Determine file type from URL
    static func from(url: URL) -> FileType {
        // Check if it's a directory first
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        
        // Get file extension
        guard let fileExtension = url.pathExtension.lowercased() as String? else {
            return .other
        }
        
        // Categorize based on extension
        switch fileExtension {
        case "txt", "rtf", "doc", "docx", "pdf", "pages", "key", "numbers", "csv", "md", "html", "htm":
            return .document
            
        case "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic", "raw", "svg":
            return .image
            
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return .video
            
        case "mp3", "wav", "aac", "flac", "ogg", "m4a":
            return .audio
            
        case "zip", "rar", "7z", "tar", "gz", "bz2", "dmg":
            return .archive
            
        case "app", "exe", "msi", "pkg", "deb", "rpm":
            return .application
            
        case "plist", "db", "sqlite", "dylib", "framework", "kext":
            return .system
            
        default:
            return .other
        }
    }
    
    // Get system image name for this file type
    var systemImageName: String {
        switch self {
        case .folder: return "folder"
        case .document: return "doc"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .application: return "app.badge"
        case .system: return "gear"
        case .other: return "doc"
        }
    }
    
    // Get default color for this file type
    var defaultColor: Color {
        switch self {
        case .folder: return .blue
        case .document: return .green
        case .image: return .purple
        case .video: return .pink
        case .audio: return .orange
        case .archive: return .yellow
        case .application: return .gray
        case .system: return .red
        case .other: return .gray
        }
    }
}

// Main model for representing files and folders
struct FileSystemItem: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let type: FileType
    let creationDate: Date?
    let modificationDate: Date?
    let accessDate: Date?
    let isPackage: Bool
    let isSymlink: Bool
    let isHidden: Bool
    var children: [FileSystemItem]?
    
    // Computed properties
    var isDirectory: Bool { type == .folder }
    var extension: String? { url.pathExtension.isEmpty ? nil : url.pathExtension }
    
    // Formatted size string
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    // Age in days
    var ageInDays: Int {
        guard let modDate = modificationDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0
    }
    
    // Relative size compared to parent (0.0 to 1.0)
    func relativeSizeToParent(_ parentSize: Int64) -> Double {
        guard parentSize > 0 else { return 0 }
        return Double(size) / Double(parentSize)
    }
    
    // Initialize from a URL with optional children
    init(url: URL, children: [FileSystemItem]? = nil) throws {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.children = children
        
        // Get file attributes
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isDirectoryKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey
        ])
        
        // Set properties from resource values
        self.isDirectory = resourceValues.isDirectory ?? false
        self.isPackage = resourceValues.isPackage ?? false
        self.isSymlink = resourceValues.isSymbolicLink ?? false
        self.isHidden = resourceValues.isHidden ?? false
        self.creationDate = resourceValues.creationDate
        self.modificationDate = resourceValues.contentModificationDate
        self.accessDate = resourceValues.contentAccessDate
        
        // Determine file type
        self.type = FileType.from(url: url)
        
        // Calculate size
        if let fileSize = resourceValues.fileSize, !isDirectory {
            self.size = Int64(fileSize)
        } else if let children = children {
            // For directories, sum up children sizes
            self.size = children.reduce(0) { $0 + $1.size }
        } else {
            // Empty directory or couldn't determine size
            self.size = 0
        }
    }
    
    // Custom initializer for testing or when file attributes are already known
    init(id: UUID = UUID(), url: URL, name: String, size: Int64, type: FileType,
         creationDate: Date? = nil, modificationDate: Date? = nil, accessDate: Date? = nil,
         isPackage: Bool = false, isSymlink: Bool = false, isHidden: Bool = false,
         children: [FileSystemItem]? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.type = type
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.accessDate = accessDate
        self.isPackage = isPackage
        self.isSymlink = isSymlink
        self.isHidden = isHidden
        self.children = children
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, url, name, size, type, creationDate, modificationDate, accessDate
        case isPackage, isSymlink, isHidden, children
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        let urlString = try container.decode(String.self, forKey: .url)
        url = URL(fileURLWithPath: urlString)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int64.self, forKey: .size)
        type = try container.decode(FileType.self, forKey: .type)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate)
        accessDate = try container.decodeIfPresent(Date.self, forKey: .accessDate)
        isPackage = try container.decode(Bool.self, forKey: .isPackage)
        isSymlink = try container.decode(Bool.self, forKey: .isSymlink)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        children = try container.decodeIfPresent([FileSystemItem].self, forKey: .children)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(url.path, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
        try container.encodeIfPresent(accessDate, forKey: .accessDate)
        try container.encode(isPackage, forKey: .isPackage)
        try container.encode(isSymlink, forKey: .isSymlink)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(children, forKey: .children)
    }
    
    // MARK: - Hashable Implementation
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// Extension for file operations
extension FileSystemItem {
    // Check if this item is a descendant of the given item
    func isDescendantOf(_ item: FileSystemItem) -> Bool {
        return url.path.hasPrefix(item.url.path) && url.path != item.url.path
    }
    
    // Get the path relative to a parent item
    func relativePath(to parent: FileSystemItem) -> String? {
        guard isDescendantOf(parent) else { return nil }
        return String(url.path.dropFirst(parent.url.path.count))
    }
    
    // Get all descendants (flattened)
    var allDescendants: [FileSystemItem] {
        var result: [FileSystemItem] = []
        if let children = children {
            for child in children {
                result.append(child)
                if child.isDirectory {
                    result.append(contentsOf: child.allDescendants)
                }
            }
        }
        return result
    }
    
    // Get the total count of all items (including descendants)
    var totalItemCount: Int {
        guard let children = children else { return 1 }
        return 1 + children.reduce(0) { $0 + $1.totalItemCount }
    }
    
    // Find an item by path
    func findItem(at path: String) -> FileSystemItem? {
        if url.path == path {
            return self
        }
        
        guard let children = children else { return nil }
        
        for child in children {
            if let found = child.findItem(at: path) {
                return found
            }
        }
        
        return nil
    }
    
    // Find items matching a predicate
    func findItems(where predicate: (FileSystemItem) -> Bool) -> [FileSystemItem] {
        var results: [FileSystemItem] = []
        
        if predicate(self) {
            results.append(self)
        }
        
        if let children = children {
            for child in children {
                results.append(contentsOf: child.findItems(where: predicate))
            }
        }
        
        return results
    }
}