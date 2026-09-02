// BinaryTreeMapCalculator.swift — Squarified TreeMap 布局计算器

import SwiftUI
import Combine
import Foundation

/// Squarified TreeMap 布局算法（Bruls/Huijsen/van Wijk 2000）。
/// 按面积比例把子节点铺进矩形，直接优化长宽比，消除细长条。
class BinaryTreeMapCalculator: ObservableObject {

    private let colorSchemeManager = ColorSchemeManager.shared
    private let minVisibleSize: CGFloat = 24
    private let maxDepth: Int = 8
    private let minFileRatio: Double = 0.01  // 小于总大小 1% 的文件归入"其他"块

    private var maxSizeByType: [FileType: Int64] = [:]

    /// 输入节点与可用矩形，输出叶子矩形列表。
    func calculateLayout(for node: TreeNode, in rect: CGRect) -> [TreeMapRectangle] {
        if rect.width < minVisibleSize || rect.height < minVisibleSize {
            return []
        }

        maxSizeByType = findMaxSizeByType(from: node)

        // 聚合"其他"块作为钻取根时需展开其内部小文件。
        if node.isAggregated {
            return binaryTreeMap(node: node, rect: rect, depth: 0, expandAggregated: true)
        }

        return binaryTreeMap(node: node, rect: rect, depth: 0)
    }

    private func binaryTreeMap(node: TreeNode, rect: CGRect, depth: Int, expandAggregated: Bool = false) -> [TreeMapRectangle] {
        let children = getValidChildren(of: node)

        if children.isEmpty {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        // 聚合"其他"块默认作为叶子绘制；仅钻取根(expandAggregated=true)时展开内部小文件。
        if node.isAggregated && !expandAggregated {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        if depth >= maxDepth {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        return squarify(children, in: rect, depth: depth)
    }

    /// 对 items 在 rect 内做 squarified 布局，递归子项。
    /// 字节数按比例缩放到 rect 像素面积后再算长宽比。
    private func squarify(_ items: [TreeNode], in rect: CGRect, depth: Int) -> [TreeMapRectangle] {
        let sorted = items.filter { $0.totalSize > 0 }.sorted { $0.totalSize > $1.totalSize }
        guard !sorted.isEmpty else { return [] }
        if sorted.count == 1 {
            return binaryTreeMap(node: sorted[0], rect: rect, depth: depth)
        }

        let totalSize = sorted.reduce(Double(0)) { $0 + Double($1.totalSize) }
        guard totalSize > 0 else { return [] }
        let totalArea = Double(rect.width * rect.height)
        let scale = (totalArea > 0) ? (totalArea / totalSize) : 0

        let scaled: [(node: TreeNode, area: Double)] = sorted.map {
            ($0, Double($0.totalSize) * scale)
        }

        var result: [TreeMapRectangle] = []
        var remaining = rect
        var row: [(node: TreeNode, area: Double)] = []
        var i = 0

        while i < scaled.count {
            let next = scaled[i]
            let tryRow = row + [next]
            let worstWith = worstAspectRatio(tryRow, in: remaining)
            let worstWithout = worstAspectRatio(row, in: remaining)

            // 加入后变差 → 固定当前行，开新行
            if !row.isEmpty && worstWith > worstWithout {
                let (laid, newRemaining) = layoutRow(row, in: remaining, depth: depth)
                result.append(contentsOf: laid)
                remaining = newRemaining
                row = []
            } else {
                row = tryRow
                i += 1
            }
        }

        if !row.isEmpty {
            let (laid, _) = layoutRow(row, in: remaining, depth: depth)
            result.append(contentsOf: laid)
        }

        return result
    }

    /// 计算一行在 rect 内的最差长宽比（越大越差，1.0 为正方形）。
    private func worstAspectRatio(_ row: [(node: TreeNode, area: Double)], in rect: CGRect) -> Double {
        guard !row.isEmpty else { return .infinity }
        let s = Double(Swift.min(rect.width, rect.height))
        guard s > 0 else { return .infinity }
        let rowArea = row.reduce(Double(0)) { $0 + $1.area }
        guard rowArea > 0 else { return .infinity }
        let w = rowArea / s
        guard w > 0 else { return .infinity }

        var worst = 0.0
        for item in row {
            let h = item.area / w
            let r = (h == 0) ? .infinity : Swift.max(w / h, h / w)
            worst = Swift.max(worst, r)
        }
        return worst
    }

    /// 沿短边方向布一行，返回（已布局矩形, 剩余矩形）。
    private func layoutRow(_ row: [(node: TreeNode, area: Double)], in rect: CGRect, depth: Int)
        -> ([TreeMapRectangle], CGRect)
    {
        let rowArea = row.reduce(Double(0)) { $0 + $1.area }

        let isWide = rect.width >= rect.height
        let s = Double(Swift.min(rect.width, rect.height))
        let w = (s > 0) ? (rowArea / s) : 0

        var result: [TreeMapRectangle] = []
        var cursor: Double = 0

        for item in row {
            let length = (rowArea > 0) ? (item.area / rowArea) * s : 0
            let subRect: CGRect
            if isWide {
                subRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + CGFloat(cursor),
                    width: CGFloat(w),
                    height: CGFloat(length)
                )
            } else {
                subRect = CGRect(
                    x: rect.minX + CGFloat(cursor),
                    y: rect.minY,
                    width: CGFloat(length),
                    height: CGFloat(w)
                )
            }
            cursor += length
            result.append(contentsOf: binaryTreeMap(node: item.node, rect: subRect, depth: depth))
        }

        let remaining: CGRect
        if isWide {
            remaining = CGRect(
                x: rect.minX + CGFloat(w),
                y: rect.minY,
                width: rect.width - CGFloat(w),
                height: rect.height
            )
        } else {
            remaining = CGRect(
                x: rect.minX,
                y: rect.minY + CGFloat(w),
                width: rect.width,
                height: rect.height - CGFloat(w)
            )
        }
        return (result, remaining)
    }

    /**
     * 获取有效子节点，含"其他"块聚合策略：
     * 1. 移除 size==0 节点（扫描边界叶子除外）
     * 2. 按大小降序，阈值 = 父目录总大小 × minFileRatio (1%)
     * 3. 保留所有 >= 阈值的子项，剩余聚合为一个虚拟"其他"节点（面积守恒，可钻取）
     * 4. 边界：若全部 < 阈值，保留前 10 大，避免空图
     */
    private func getValidChildren(of parent: TreeNode) -> [TreeNode] {
        let boundaryChildren = parent.children.filter { $0.scanBoundary != .normal }
        let nonZeroChildren = parent.children.filter {
            $0.scanBoundary == .normal && $0.totalSize > 0
        }
        guard !nonZeroChildren.isEmpty || !boundaryChildren.isEmpty else { return [] }

        if nonZeroChildren.count <= 5 {
            return nonZeroChildren + boundaryChildren
        }

        let sortedChildren = nonZeroChildren.sorted { $0.totalSize > $1.totalSize }
        let totalSize = sortedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        let threshold = Int64(Double(totalSize) * minFileRatio)

        var kept: [TreeNode] = []
        var aggregatedChildren: [TreeNode] = []

        for child in sortedChildren {
            if child.totalSize >= threshold {
                kept.append(child)
            } else {
                aggregatedChildren.append(child)
            }
        }

        if kept.isEmpty {
            return Array(sortedChildren.prefix(10)) + boundaryChildren
        }

        if aggregatedChildren.isEmpty {
            return kept + boundaryChildren
        }

        // 虚拟"其他"节点：isDirectory 保持 false，使 totalSize 走文件分支返回 item.size（面积守恒）。
        let aggregatedSize = aggregatedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        let otherItem = FileSystemItem(
            name: "其他 (\(aggregatedChildren.count) 项)",
            path: URL(fileURLWithPath: "/__aggregated__"),
            size: aggregatedSize,
            isDirectory: false
        )
        let otherNode = TreeNode(item: otherItem, parent: parent)
        otherNode.markAsAggregated()
        for child in aggregatedChildren {
            otherNode.addChild(child)
        }

        return kept + [otherNode]
    }

    /// 查找每个 FileType 在子树内的最大叶子文件大小，用于颜色深度基准。
    private func findMaxSizeByType(from node: TreeNode) -> [FileType: Int64] {
        var result: [FileType: Int64] = [:]

        func traverse(_ current: TreeNode) {
            // 聚合"其他"块 isDirectory 为 false 但持有内部小文件，穿透遍历。
            if current.item.isDirectory || current.isAggregated {
                current.children.forEach { traverse($0) }
            } else {
                let ft = FileType.from(extension: current.item.fileExtension)
                let cur = result[ft] ?? 0
                if current.totalSize > cur {
                    result[ft] = current.totalSize
                }
            }
        }
        traverse(node)
        return result
    }

    private func createLeafRectangle(node: TreeNode, rect: CGRect, depth: Int) -> TreeMapRectangle {
        let color: Color
        if node.scanBoundary == .crossVolume {
            color = Color(.systemGray).opacity(0.35)
        } else if node.scanBoundary == .alreadyCounted {
            color = Color(.systemGray).opacity(0.22)
        } else if node.scanBoundary == .symlink {
            color = Color(.systemGray).opacity(0.18)
        } else if node.isAggregated {
            color = Color(.systemGray).opacity(0.5)
        } else if node.item.isDirectory {
            color = colorSchemeManager.colorForDirectory().opacity(0.7)
        } else {
            let ft = FileType.from(extension: node.item.fileExtension)
            let maxSizeInType = maxSizeByType[ft] ?? node.totalSize
            color = colorSchemeManager.depthColor(for: node, maxSizeInType: maxSizeInType)
        }
        return TreeMapRectangle(
            node: node,
            rect: rect,
            color: color,
            level: depth,
            isAggregated: node.isAggregated
        )
    }
}
