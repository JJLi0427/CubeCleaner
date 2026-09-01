// ColorSchemeManager.swift — 颜色方案管理器

import SwiftUI
import AppKit
import Foundation

// MARK: - 可视化模块
// MARK: ColorSchemeManager - 颜色方案管理器
/// 统一的颜色方案管理器
/// 负责为不同类型的文件和文件夹分配颜色
///
/// 特性：
/// - 单例模式，全局一致的颜色方案
/// - 基于文件类型的智能配色
/// - 支持动态透明度调整
/// - 文件夹和文件的区分显示
class ColorSchemeManager: ObservableObject {
    static let shared = ColorSchemeManager()

    /// 高饱和调色板（v0.3）— 固定 RGB，不做亮/暗分别调色
    private let fileTypeColors: [FileType: Color] = [
        .document: Color(red: 0.039, green: 0.518, blue: 1.0),     // #0A84FF
        .image: Color(red: 0.188, green: 0.820, blue: 0.345),      // #30D158
        .video: Color(red: 1.0, green: 0.271, blue: 0.227),        // #FF453A
        .audio: Color(red: 0.749, green: 0.353, blue: 0.949),      // #BF5AF2
        .archive: Color(red: 1.0, green: 0.624, blue: 0.039),      // #FF9F0A
        .application: Color(red: 0.392, green: 0.824, blue: 1.0),  // #64D2FF
        .system: Color(red: 1.0, green: 0.839, blue: 0.039),       // #FFD60A
        .other: Color(red: 1.0, green: 0.216, blue: 0.373),        // #FF375F
    ]

    /// 文件夹专用颜色（高饱和深青）
    private let directoryColor: Color = Color(red: 0.251, green: 0.784, blue: 0.878)  // #40C8E0

    private init() {}

    /// 获取节点对应的颜色
    func color(for node: TreeNode) -> Color {
        if node.item.isDirectory {
            return directoryColor.opacity(0.7)
        }

        let fileType = FileType.from(extension: node.item.fileExtension)
        return fileTypeColors[fileType] ?? .gray
    }

    /// 获取文件类型对应的颜色
    func color(for fileType: FileType) -> Color {
        return fileTypeColors[fileType] ?? .gray
    }

    /// 获取文件夹颜色
    func colorForDirectory() -> Color {
        return directoryColor
    }

    /// 按类型内最大块为基准调亮度：ratio=1(类型内最大)→原色最深，ratio→0→向浅提亮。
    /// 提亮公式：c' = c + (1-c)*(1-ratio)*0.6。文件夹/聚合由调用方处理，本方法仅处理普通文件。
    func depthColor(for node: TreeNode, maxSizeInType: Int64) -> Color {
        let baseColor = color(for: node)
        guard maxSizeInType > 0 else { return baseColor }
        let ratio = Double(node.totalSize) / Double(maxSizeInType)
        let clampedRatio = min(max(ratio, 0.0), 1.0)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(baseColor).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

        let k: Double = 0.6
        let lighten = (1.0 - clampedRatio) * k
        let nr = r + (1.0 - r) * lighten
        let ng = g + (1.0 - g) * lighten
        let nb = b + (1.0 - b) * lighten
        return Color(red: nr, green: ng, blue: nb)
    }

    /// 类型占比条目（供统计条比例条与图例侧栏共用）
    struct TypeBreakdownEntry: Identifiable {
        var id: FileType { type }
        let type: FileType
        let size: Int64
        let color: Color
        var ratio: CGFloat {      // size / total；total=0 时外部不渲染
            total > 0 ? CGFloat(size) / CGFloat(total) : 0
        }
        let total: Int64
    }

    /// 聚合 node 子树所有叶子文件，按 FileType 累加 item.size。
    /// 文件夹不计入（避免与子文件重复）。返回 8 类型（含 size=0），按 size 降序。
    func typeBreakdown(for node: TreeNode) -> [TypeBreakdownEntry] {
        var sizes: [FileType: Int64] = [:]
        for type in FileType.allCases { sizes[type] = 0 }

        func traverse(_ current: TreeNode) {
            // 聚合"其他"块 isDirectory 为 false（面积守恒设计），但持有 children，
            // 钻取后须穿透它遍历内部小文件，否则会被当成单个叶子文件。
            if current.item.isDirectory || current.isAggregated {
                for child in current.children { traverse(child) }
            } else {
                let ft = FileType.from(extension: current.item.fileExtension)
                sizes[ft, default: 0] += current.item.size
            }
        }
        traverse(node)

        let total = sizes.values.reduce(Int64(0), +)
        return FileType.allCases
            .map { TypeBreakdownEntry(type: $0, size: sizes[$0] ?? 0, color: color(for: $0), total: total) }
            .sorted { $0.size > $1.size }
    }

    /// 统计 node 子树的叶子文件数（非目录）。
    /// 聚合"其他"块 isDirectory 为 false，需穿透其 children 统计内部文件。
    func fileCountInSubtree(_ node: TreeNode) -> Int {
        if node.item.isDirectory || node.isAggregated {
            return node.children.reduce(0) { $0 + fileCountInSubtree($1) }
        } else {
            return 1
        }
    }

    /// 统计 node 子树的目录数（含 node 自身若为目录）
    func folderCountInSubtree(_ node: TreeNode) -> Int {
        if node.isAggregated {
            return node.children.reduce(0) { $0 + folderCountInSubtree($1) }
        }
        let selfCount = node.item.isDirectory ? 1 : 0
        return selfCount + node.children.reduce(0) { $0 + folderCountInSubtree($1) }
    }
}
