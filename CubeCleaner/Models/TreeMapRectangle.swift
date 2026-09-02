// TreeMapRectangle.swift — TreeMap矩形结构

import SwiftUI
import Foundation

/// TreeMap 中的单个矩形元素，含显示与交互信息。
struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let level: Int
    let isAggregated: Bool

    /// 矩形足够大才显示标签
    var shouldShowLabel: Bool {
        return rect.width > 50 && rect.height > 20
    }

    /// 根据可用空间自适应截断显示名称（优先保留文件扩展名）
    var displayName: String {
        let availableWidth = rect.width - 8
        let estimatedCharWidth: CGFloat = 7
        let maxChars = Int(availableWidth / estimatedCharWidth)

        guard maxChars > 3 else { return "" }

        let name = node.item.name
        if name.count <= maxChars {
            return name
        } else {
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
            return String(name.prefix(maxChars - 3)) + "..."
        }
    }

    var canShowSize: Bool {
        return rect.width > 80 && rect.height > 35
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file)
    }

    /// 大于 10MB 视为重要节点
    var isImportant: Bool {
        return node.totalSize > 10_000_000
    }
}
