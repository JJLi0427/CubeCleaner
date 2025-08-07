//
//  ScanResult.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation

// Struct to represent the result of a disk scan operation
struct ScanResult: Identifiable, Codable {
    let id: UUID
    let rootItem: FileSystemItem
    let scanDate: Date
    let scanPath: URL
    let excludedPaths: [String]
    let scanDepth: Int?
    let excludedSystemFiles: Bool
    let excludedHiddenFiles: Bool
    
    // Computed properties
    var totalSize: Int64 { rootItem.size }
    var itemCount: Int { rootItem.totalItemCount }
    
    // Initialize with a root item and scan parameters
    init(
        rootItem: FileSystemItem,
        scanPath: URL,
        excludedPaths: [String] = [],
        scanDepth: Int? = nil,
        excludedSystemFiles: Bool = true,
        excludedHiddenFiles: Bool = true
    ) {
        self.id = UUID()
        self.rootItem = rootItem
        self.scanDate = Date()
        self.scanPath = scanPath
        self.excludedPaths = excludedPaths
        self.scanDepth = scanDepth
        self.excludedSystemFiles = excludedSystemFiles
        self.excludedHiddenFiles = excludedHiddenFiles
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, rootItem, scanDate, scanPath, excludedPaths, scanDepth
        case excludedSystemFiles, excludedHiddenFiles
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        rootItem = try container.decode(FileSystemItem.self, forKey: .rootItem)
        scanDate = try container.decode(Date.self, forKey: .scanDate)
        
        let scanPathString = try container.decode(String.self, forKey: .scanPath)
        scanPath = URL(fileURLWithPath: scanPathString)
        
        excludedPaths = try container.decode([String].self, forKey: .excludedPaths)
        scanDepth = try container.decodeIfPresent(Int.self, forKey: .scanDepth)
        excludedSystemFiles = try container.decode(Bool.self, forKey: .excludedSystemFiles)
        excludedHiddenFiles = try container.decode(Bool.self, forKey: .excludedHiddenFiles)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(rootItem, forKey: .rootItem)
        try container.encode(scanDate, forKey: .scanDate)
        try container.encode(scanPath.path, forKey: .scanPath)
        try container.encode(excludedPaths, forKey: .excludedPaths)
        try container.encodeIfPresent(scanDepth, forKey: .scanDepth)
        try container.encode(excludedSystemFiles, forKey: .excludedSystemFiles)
        try container.encode(excludedHiddenFiles, forKey: .excludedHiddenFiles)
    }
}

// Extension for scan result operations
extension ScanResult {
    // Get a formatted description of the scan
    var description: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        let dateString = formatter.string(from: scanDate)
        let sizeString = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        
        return "Scan of \(scanPath.lastPathComponent) - \(itemCount) items, \(sizeString) - \(dateString)"
    }
    
    // Find the largest items in the scan result
    func largestItems(limit: Int = 10) -> [FileSystemItem] {
        let allItems = rootItem.allDescendants + [rootItem]
        return allItems.sorted { $0.size > $1.size }.prefix(limit).map { $0 }
    }
    
    // Find the oldest items in the scan result
    func oldestItems(limit: Int = 10) -> [FileSystemItem] {
        let allItems = rootItem.allDescendants + [rootItem]
        return allItems
            .filter { $0.modificationDate != nil }
            .sorted { ($0.modificationDate ?? Date()) < ($1.modificationDate ?? Date()) }
            .prefix(limit)
            .map { $0 }
    }
    
    // Find items by type
    func itemsByType(_ type: FileType) -> [FileSystemItem] {
        return rootItem.findItems { $0.type == type }
    }
    
    // Find items by name pattern
    func itemsMatchingName(_ pattern: String) -> [FileSystemItem] {
        return rootItem.findItems { $0.name.range(of: pattern, options: .caseInsensitive) != nil }
    }
    
    // Get size distribution by file type
    func sizeDistributionByType() -> [FileType: Int64] {
        let allItems = rootItem.allDescendants + [rootItem]
        var distribution: [FileType: Int64] = [:]
        
        for item in allItems {
            distribution[item.type, default: 0] += item.size
        }
        
        return distribution
    }
    
    // Get items modified within a date range
    func itemsModifiedBetween(startDate: Date, endDate: Date) -> [FileSystemItem] {
        return rootItem.findItems { item in
            guard let modDate = item.modificationDate else { return false }
            return modDate >= startDate && modDate <= endDate
        }
    }
    
    // Compare with another scan result to find differences
    func differences(from otherScan: ScanResult) -> ScanDifference {
        let currentItems = (rootItem.allDescendants + [rootItem]).reduce(into: [String: FileSystemItem]()) { dict, item in
            dict[item.url.path] = item
        }
        
        let otherItems = (otherScan.rootItem.allDescendants + [otherScan.rootItem]).reduce(into: [String: FileSystemItem]()) { dict, item in
            dict[item.url.path] = item
        }
        
        var added: [FileSystemItem] = []
        var removed: [FileSystemItem] = []
        var modified: [(current: FileSystemItem, previous: FileSystemItem)] = []
        
        // Find added and modified items
        for (path, currentItem) in currentItems {
            if let otherItem = otherItems[path] {
                // Item exists in both scans
                if currentItem.size != otherItem.size || currentItem.modificationDate != otherItem.modificationDate {
                    modified.append((current: currentItem, previous: otherItem))
                }
            } else {
                // Item exists only in current scan
                added.append(currentItem)
            }
        }
        
        // Find removed items
        for (path, otherItem) in otherItems {
            if currentItems[path] == nil {
                removed.append(otherItem)
            }
        }
        
        return ScanDifference(added: added, removed: removed, modified: modified)
    }
}

// Struct to represent differences between two scan results
struct ScanDifference {
    let added: [FileSystemItem]
    let removed: [FileSystemItem]
    let modified: [(current: FileSystemItem, previous: FileSystemItem)]
    
    // Computed properties
    var addedSize: Int64 { added.reduce(0) { $0 + $1.size } }
    var removedSize: Int64 { removed.reduce(0) { $0 + $1.size } }
    var modifiedSizeDelta: Int64 {
        modified.reduce(0) { $0 + ($1.current.size - $1.previous.size) }
    }
    
    var totalSizeDelta: Int64 { addedSize - removedSize + modifiedSizeDelta }
    var hasChanges: Bool { !added.isEmpty || !removed.isEmpty || !modified.isEmpty }
}

// Extension for ByteCountFormatter to make it easier to use
extension ByteCountFormatter {
    static func string(fromByteCount byteCount: Int64, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = countStyle
        return formatter.string(fromByteCount: byteCount)
    }
}