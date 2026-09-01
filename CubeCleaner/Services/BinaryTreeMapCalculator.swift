// BinaryTreeMapCalculator.swift — Binary Tree TreeMap 布局计算器

import SwiftUI
import Combine
import Foundation

// MARK: - Binary Tree TreeMap 布局计算器
/// Binary Tree TreeMap算法实现
/// Linus式设计原则：消除特殊情况，最简数据结构，零废话
///
/// 核心思想：
/// 1. 把复杂的Squarified算法扔掉 - 它是过度设计的垃圾
/// 2. 用Binary Tree简单二分法：大的一半，小的一半，完事
/// 3. 没有特殊情况，没有复杂计算，就是递归二分
/// 4. 数据结构决定算法 - TreeMap就是个Binary Tree的可视化
class BinaryTreeMapCalculator: ObservableObject {

    // MARK: - 核心常量 - 实用主义优先
    private let colorSchemeManager = ColorSchemeManager.shared
    private let minVisibleSize: CGFloat = 24  // 最小可见尺寸：24x24像素，用户能看清
    private let maxDepth: Int = 8  // 限制递归深度，避免过度分割
    private let minFileRatio: Double = 0.01  // 聚合阈值：小于总大小1%的文件归入"其他"块

    // MARK: - 全局状态 - 一个变量搞定颜色
    private var maxSizeByType: [FileType: Int64] = [:]

    // MARK: - 主入口 - 就这一个函数，其他都是实现细节
    /**
     * Binary Tree TreeMap主算法
     * 输入：节点和矩形 -> 输出：矩形列表
     * 没有花哨的东西，就是递归二分
     */
    func calculateLayout(for node: TreeNode, in rect: CGRect) -> [TreeMapRectangle] {
        // 太小就不画，实用主义
        if rect.width < minVisibleSize || rect.height < minVisibleSize {
            return []
        }

        // 设置全局最大值，用于颜色和阈值计算
        maxSizeByType = findMaxSizeByType(from: node)

        // 入口为聚合"其他"块：用户双击钻取进来，需展开其内部小文件。
        // 普通目录走默认分支；聚合节点只有在作为钻取根时才展开。
        if node.isAggregated {
            return binaryTreeMap(node: node, rect: rect, depth: 0, expandAggregated: true)
        }

        // 开始递归
        return binaryTreeMap(node: node, rect: rect, depth: 0)
    }

    // MARK: - 核心算法 - Binary Tree递归分割
    /**
     * Binary Tree核心算法 - 重新设计版本
     *
     * Linus式设计原则：
     * 1. 消除虚拟节点 - 它们是过度设计的垃圾
     * 2. 直接处理节点数组 - 简单粗暴有效
     * 3. 没有特殊情况 - 递归到底
     */
    private func binaryTreeMap(node: TreeNode, rect: CGRect, depth: Int, expandAggregated: Bool = false) -> [TreeMapRectangle] {
        // 获取有效子节点
        let children = getValidChildren(of: node)

        // 递归终止：没有子节点就画叶子
        if children.isEmpty {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        // 聚合"其他"块：默认作为叶子矩形直接绘制，不参与递归二分。
        // 当它是用户双击钻取的根节点时(expandAggregated=true)，
        // 需展开其内部小文件供查看，越过此叶子逻辑继续递归。
        if node.isAggregated && !expandAggregated {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        // 太深了：节点作为单块叶子绘制，不再细分（避免线性切片制造细长条）
        if depth >= maxDepth {
            return [createLeafRectangle(node: node, rect: rect, depth: depth)]
        }

        // Squarified 布局：优化长宽比让块尽量方
        return squarify(children, in: rect, depth: depth)
    }

    // MARK: - Squarified Treemap（Bruls/Huijsen/van Wijk 2000）
    // 直接优化长宽比，消除细长小条。

    /// 对 items 在 rect 内做 squarified 布局，递归子项。
    /// 字节数按比例缩放到 rect 像素面积后再算长宽比，避免单位不匹配。
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

        // 节点 + 缩放后面积（像素²），后续长宽比/带宽全用面积算
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
                // 不前进 i，next 留到下一行
            } else {
                row = tryRow
                i += 1
            }
        }

        // 冲刷最后一行
        if !row.isEmpty {
            let (laid, _) = layoutRow(row, in: remaining, depth: depth)
            result.append(contentsOf: laid)
        }

        return result
    }

    /// 计算一行在 rect 内的最差长宽比（越大越差，1.0 为正方形）。
    /// row 用缩放后面积（像素²），rect 用像素。
    private func worstAspectRatio(_ row: [(node: TreeNode, area: Double)], in rect: CGRect) -> Double {
        guard !row.isEmpty else { return .infinity }
        let s = Double(Swift.min(rect.width, rect.height))
        guard s > 0 else { return .infinity }
        let rowArea = row.reduce(Double(0)) { $0 + $1.area }
        guard rowArea > 0 else { return .infinity }
        let w = rowArea / s  // 行的带宽厚度（像素）
        guard w > 0 else { return .infinity }

        // 每项 h_i = itemArea / w（像素），长宽比 max(w/h_i, h_i/w)
        var worst = 0.0
        for item in row {
            let h = item.area / w
            let r = (h == 0) ? .infinity : Swift.max(w / h, h / w)
            worst = Swift.max(worst, r)
        }
        return worst
    }

    /// 沿短边方向布一行，返回（已布局矩形, 剩余矩形）。
    /// row 用缩放后面积（像素²）。
    private func layoutRow(_ row: [(node: TreeNode, area: Double)], in rect: CGRect, depth: Int)
        -> ([TreeMapRectangle], CGRect)
    {
        let rowArea = row.reduce(Double(0)) { $0 + $1.area }

        let isWide = rect.width >= rect.height
        let s = Double(Swift.min(rect.width, rect.height))  // 行沿此边布
        let w = (s > 0) ? (rowArea / s) : 0  // 带宽厚度（像素）

        var result: [TreeMapRectangle] = []
        var cursor: Double = 0  // 行内累计长度（像素）

        for item in row {
            let length = (rowArea > 0) ? (item.area / rowArea) * s : 0  // 该项沿短边方向占的长度（像素）
            let subRect: CGRect
            if isWide {
                // 带在左侧（宽 w，满高），项沿高度方向排
                subRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + CGFloat(cursor),
                    width: CGFloat(w),
                    height: CGFloat(length)
                )
            } else {
                // 带在顶部（高 w，满宽），项沿宽度方向排
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

        // 剩余矩形：去掉带宽 w 的一侧
        let remaining: CGRect
        if isWide {
            // 带占左侧 [0, w]，剩余在右
            remaining = CGRect(
                x: rect.minX + CGFloat(w),
                y: rect.minY,
                width: rect.width - CGFloat(w),
                height: rect.height
            )
        } else {
            // 带占顶部 [0, w]，剩余在下
            remaining = CGRect(
                x: rect.minX,
                y: rect.minY + CGFloat(w),
                width: rect.width,
                height: rect.height - CGFloat(w)
            )
        }
        return (result, remaining)
    }

    // MARK: - 工具函数 - 简单直接，没有复杂逻辑

    /**
     * 获取有效子节点 - 聚合"其他"块策略
     *
     * 规则：
     * 1. 移除大小为0的节点
     * 2. 按大小降序排序
     * 3. 阈值 = 父目录总大小 × minFileRatio (1%)
     * 4. 保留所有 >= 阈值的子项
     * 5. 剩余子项聚合为一个虚拟"其他"节点（面积守恒，保留子项以支持双击钻取）
     * 6. 边界：若全部 < 阈值，不聚合，保留前 10 大，避免空图
     */
    private func getValidChildren(of parent: TreeNode) -> [TreeNode] {
        // 扫描边界叶子（跨卷/符号链接/已计入）即使 size==0 也保留，让它们在 TreeMap 上可见。
        // 其余 size==0 的子项按原逻辑过滤。
        let boundaryChildren = parent.children.filter { $0.scanBoundary != .normal }
        let nonZeroChildren = parent.children.filter {
            $0.scanBoundary == .normal && $0.totalSize > 0
        }
        guard !nonZeroChildren.isEmpty || !boundaryChildren.isEmpty else { return [] }

        // 子节点不多，直接返回（含边界叶子）
        if nonZeroChildren.count <= 5 {
            return nonZeroChildren + boundaryChildren
        }

        let sortedChildren = nonZeroChildren.sorted { $0.totalSize > $1.totalSize }
        let totalSize = sortedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        let threshold = Int64(Double(totalSize) * minFileRatio)

        // 分离保留项与待聚合项
        var kept: [TreeNode] = []
        var aggregatedChildren: [TreeNode] = []

        for child in sortedChildren {
            if child.totalSize >= threshold {
                kept.append(child)
            } else {
                aggregatedChildren.append(child)
            }
        }

        // 边界：若全部 < 阈值（即 kept 为空），保留前 10 大，不聚合
        if kept.isEmpty {
            return Array(sortedChildren.prefix(10)) + boundaryChildren
        }

        // 没有可聚合的小文件，直接返回（含边界叶子）
        if aggregatedChildren.isEmpty {
            return kept + boundaryChildren
        }

        // 构造虚拟"其他"节点 - 把待聚合的子项挂为它的 children，
        // 这样双击该块可钻取进去看内部小文件。
        // 注意：isDirectory 保持 false，使 totalSize 走文件分支返回 item.size，
        // 保证面积守恒（若为 true 会叠加 children 总大小导致面积翻倍）。
        let aggregatedSize = aggregatedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        let otherItem = FileSystemItem(
            name: "其他 (\(aggregatedChildren.count) 项)",
            path: URL(fileURLWithPath: "/__aggregated__"),
            size: aggregatedSize,
            isDirectory: false
        )
        let otherNode = TreeNode(item: otherItem, parent: parent)
        otherNode.markAsAggregated()
        // 复用原有子节点（不改其 parent），仅挂到 otherNode.children 下，
        // 供钻取后布局使用；面包屑只需沿 otherNode.parent 上溯即可。
        // 聚合节点 totalSize 保持 item.size（面积守恒，见 computeTotalSize 的 isAggregated 短路）。
        for child in aggregatedChildren {
            otherNode.addChild(child)
        }

        return kept + [otherNode]
    }

    /**
     * 查找每个 FileType 在子树内的最大叶子文件大小 - 用于颜色深度基准
     */
    private func findMaxSizeByType(from node: TreeNode) -> [FileType: Int64] {
        var result: [FileType: Int64] = [:]

        func traverse(_ current: TreeNode) {
            // 聚合"其他"块 isDirectory 为 false，但持有内部小文件，穿透遍历，
            // 否则整块被当成单个 .other 文件，撑大 .other 的深度配色基准。
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

    /**
     * 创建叶子矩形 - 就是包装一下数据
     */
    private func createLeafRectangle(node: TreeNode, rect: CGRect, depth: Int, isAggregated: Bool = false) -> TreeMapRectangle {
        let color: Color
        if node.scanBoundary == .crossVolume {
            // 跨挂载点卷：未计入，用半透明中性灰区分
            color = Color(.systemGray).opacity(0.35)
        } else if node.scanBoundary == .alreadyCounted {
            // 硬链接/firmlink 已计入：更浅的灰
            color = Color(.systemGray).opacity(0.22)
        } else if node.scanBoundary == .symlink {
            // 符号链接：最浅灰
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
