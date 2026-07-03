// TreeMapRectangle.swift — TreeMap矩形结构

import SwiftUI
import Foundation

// MARK: TreeMapRectangle - TreeMap矩形结构
/// TreeMap可视化中的单个矩形元素
/// 包含显示逻辑和交互信息
///
/// 特性：
/// - 自适应标签显示：根据矩形大小决定显示内容
/// - 智能文本截断：保留重要信息（如文件扩展名）
/// - 分层显示控制：不同层级的显示策略
/// - 重要性判断：用于优化显示效果
struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let level: Int
    let isAggregated: Bool  // 是否为聚合的"其他"块

    /**
     * 是否显示标签的判断逻辑
     * 基于矩形的实际可视大小，确保标签可读性
     */
    var shouldShowLabel: Bool {
        // 矩形需要足够大才显示标签
        return rect.width > 50 && rect.height > 20
    }

    /**
     * 智能显示名称
     * 根据可用空间自动调整显示内容
     */
    var displayName: String {
        let availableWidth = rect.width - 8  // 减去padding
        let estimatedCharWidth: CGFloat = 7  // 估算字符宽度
        let maxChars = Int(availableWidth / estimatedCharWidth)

        guard maxChars > 3 else { return "" }

        let name = node.item.name
        if name.count <= maxChars {
            return name
        } else {
            // 智能截断：保留文件扩展名
            if !node.item.isDirectory && name.contains(".") {
                let components = name.split(separator: ".", maxSplits: 1)
                if components.count == 2 {
                    let namepart = String(components[0])
                    let ext = String(components[1])
                    let availableForName = maxChars - ext.count - 4  // "...ext"
                    if availableForName > 0 {
                        return String(namepart.prefix(availableForName)) + "..." + ext
                    }
                }
            }
            // 普通截断
            return String(name.prefix(maxChars - 3)) + "..."
        }
    }

    /**
     * 是否显示大小信息
     * 只有在矩形足够大的情况下才显示
     */
    var canShowSize: Bool {
        return rect.width > 80 && rect.height > 35
    }

    /**
     * 是否显示详细信息（文件数量等）
     */
    var canShowDetails: Bool {
        return rect.width > 120 && rect.height > 50
    }

    /**
     * 格式化的大小字符串
     */
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file)
    }

    /**
     * 矩形的重要程度（用于决定显示优先级）
     * 基于大小和层级
     */
    var importance: Double {
        let sizeWeight = Double(node.totalSize)
        let levelWeight = 1.0 / Double(level + 1)  // 层级越深权重越小
        return sizeWeight * levelWeight
    }

    /**
     * 是否为重要节点（大文件/文件夹）
     */
    var isImportant: Bool {
        return node.totalSize > 10_000_000  // 大于10MB认为是重要的
    }

    /**
     * 获取子文件数量描述
     */
    var childrenDescription: String {
        guard node.item.isDirectory else { return "" }
        let count = node.children.count
        if count == 0 {
            return "空文件夹"
        } else {
            return "\(count) 项"
        }
    }
}
