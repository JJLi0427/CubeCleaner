//
//  VolumeInfo.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation

/// 卷信息模型
/// 表示系统中的存储卷（磁盘、分区等）
struct VolumeInfo: Identifiable, Hashable {
    // MARK: - Properties
    
    /// 唯一标识符
    let id = UUID()
    
    /// 卷名称
    let name: String
    
    /// 卷路径
    let url: URL
    
    /// 总容量（字节）
    let totalCapacity: Int64
    
    /// 可用容量（字节）
    let availableCapacity: Int64
    
    /// 是否为可移动媒体
    let isRemovable: Bool
    
    /// 是否为内部存储
    let isInternal: Bool
    
    /// 是否为本地存储
    let isLocal: Bool
    
    /// 文件系统类型
    let fileSystemType: String?
    
    // MARK: - Computed Properties
    
    /// 已使用容量
    var usedCapacity: Int64 {
        return totalCapacity - availableCapacity
    }
    
    /// 使用率（0.0 - 1.0）
    var usageRatio: Double {
        guard totalCapacity > 0 else { return 0.0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
    
    /// 使用百分比
    var usagePercentage: Int {
        return Int(usageRatio * 100)
    }
    
    /// 卷类型描述
    var typeDescription: String {
        if isRemovable {
            return "可移动磁盘"
        } else if !isLocal {
            return "网络磁盘"
        } else if isInternal {
            return "内置磁盘"
        } else {
            return "外置磁盘"
        }
    }
    
    /// 格式化的总容量
    var formattedTotalCapacity: String {
        return ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }
    
    /// 格式化的可用容量
    var formattedAvailableCapacity: String {
        return ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }
    
    /// 格式化的已使用容量
    var formattedUsedCapacity: String {
        return ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }
    
    /// 卷图标名称（SF Symbols）
    var iconName: String {
        if isRemovable {
            return "externaldrive.connected"
        } else if !isLocal {
            return "network"
        } else if name.lowercased().contains("boot") || name.lowercased().contains("macintosh") {
            return "internaldrive"
        } else {
            return "externaldrive"
        }
    }
    
    // MARK: - Initialization
    
    /// 初始化卷信息
    init(name: String,
         url: URL,
         totalCapacity: Int64,
         availableCapacity: Int64,
         isRemovable: Bool = false,
         isInternal: Bool = true,
         isLocal: Bool = true,
         fileSystemType: String? = nil) {
        
        self.name = name
        self.url = url
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.isRemovable = isRemovable
        self.isInternal = isInternal
        self.isLocal = isLocal
        self.fileSystemType = fileSystemType
    }
    
    /// 从 URL 创建卷信息
    /// - Parameter url: 卷的挂载点 URL
    /// - Returns: 卷信息实例，创建失败返回 nil
    static func from(url: URL) -> VolumeInfo? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey,
                .volumeIsInternalKey,
                .volumeIsLocalKey,
                .volumeLocalizedFormatDescriptionKey
            ])
            
            let name = resourceValues.volumeName ?? url.lastPathComponent
            let totalCapacity = Int64(resourceValues.volumeTotalCapacity ?? 0)
            let availableCapacity = Int64(resourceValues.volumeAvailableCapacity ?? 0)
            let isRemovable = resourceValues.volumeIsRemovable ?? false
            let isInternal = resourceValues.volumeIsInternal ?? true
            let isLocal = resourceValues.volumeIsLocal ?? true
            let fileSystemType = resourceValues.volumeLocalizedFormatDescription
            
            return VolumeInfo(
                name: name,
                url: url,
                totalCapacity: totalCapacity,
                availableCapacity: availableCapacity,
                isRemovable: isRemovable,
                isInternal: isInternal,
                isLocal: isLocal,
                fileSystemType: fileSystemType
            )
        } catch {
            print("Error creating VolumeInfo from URL \(url): \(error)")
            return nil
        }
    }
    
    // MARK: - Utility Methods
    
    /// 检查是否有足够的可用空间
    /// - Parameter requiredSpace: 需要的空间大小（字节）
    /// - Returns: 是否有足够空间
    func hasEnoughSpace(_ requiredSpace: Int64) -> Bool {
        return availableCapacity >= requiredSpace
    }
    
    /// 获取空间警告状态
    var spaceWarningLevel: SpaceWarningLevel {
        let freeRatio = Double(availableCapacity) / Double(totalCapacity)
        
        if freeRatio < 0.05 { // 少于5%
            return .critical
        } else if freeRatio < 0.1 { // 少于10%
            return .warning
        } else if freeRatio < 0.2 { // 少于20%
            return .caution
        } else {
            return .normal
        }
    }
    
    /// 获取详细信息字典
    func detailedInfo() -> [String: Any] {
        return [
            "name": name,
            "path": url.path,
            "totalCapacity": totalCapacity,
            "availableCapacity": availableCapacity,
            "usedCapacity": usedCapacity,
            "usagePercentage": usagePercentage,
            "isRemovable": isRemovable,
            "isInternal": isInternal,
            "isLocal": isLocal,
            "fileSystemType": fileSystemType ?? "未知",
            "typeDescription": typeDescription
        ]
    }
    
    // MARK: - Hashable & Equatable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    static func == (lhs: VolumeInfo, rhs: VolumeInfo) -> Bool {
        return lhs.url == rhs.url
    }
}

// MARK: - Supporting Types

/// 空间警告级别
enum SpaceWarningLevel: CaseIterable {
    case normal
    case caution
    case warning
    case critical
    
    var description: String {
        switch self {
        case .normal: return "正常"
        case .caution: return "注意"
        case .warning: return "警告"
        case .critical: return "严重"
        }
    }
    
    var colorName: String {
        switch self {
        case .normal: return "green"
        case .caution: return "yellow"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
    
    var iconName: String {
        switch self {
        case .normal: return "checkmark.circle"
        case .caution: return "exclamationmark.triangle"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
}
