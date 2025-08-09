//
//  TreeMapLayoutCalculator.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation
import CoreGraphics

/// 树状图布局计算器
/// 实现 Squarified Treemap 算法，为树状数据生成优化的矩形布局
class TreeMapLayoutCalculator {
    
    // MARK: - Layout Configuration
    
    /// 布局配置
    struct LayoutConfiguration {
        /// 最小矩形大小（像素）
        let minimumSize: CGFloat
        
        /// 间距大小
        let spacing: CGFloat
        
        /// 是否启用递归布局
        let enableRecursiveLayout: Bool
        
        /// 最大递归深度
        let maxRecursionDepth: Int
        
        /// 长宽比优化权重
        let aspectRatioWeight: Double
        
        static let `default` = LayoutConfiguration(
            minimumSize: 4.0,
            spacing: 1.0,
            enableRecursiveLayout: true,
            maxRecursionDepth: 10,
            aspectRatioWeight: 1.0
        )
    }
    
    // MARK: - Properties
    
    private let configuration: LayoutConfiguration
    
    // MARK: - Initialization
    
    init(configuration: LayoutConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Public Interface
    
    /// 计算树状图布局
    /// - Parameters:
    ///   - node: 根节点
    ///   - bounds: 可用的布局区域
    /// - Returns: 布局是否成功
    @discardableResult
    func calculateLayout(for node: TreeNode, in bounds: CGRect) -> Bool {
        // 重置所有布局状态
        node.resetLayoutCalculation()
        
        // 开始递归布局计算
        return calculateLayoutRecursively(
            node: node,
            bounds: bounds,
            depth: 0
        )
    }
    
    // MARK: - Private Implementation
    
    /// 递归计算布局
    private func calculateLayoutRecursively(
        node: TreeNode,
        bounds: CGRect,
        depth: Int
    ) -> Bool {
        
        // 检查深度限制
        guard depth < configuration.maxRecursionDepth else {
            node.setLayoutRect(bounds)
            return true
        }
        
        // 设置当前节点的布局
        node.setLayoutRect(bounds)
        
        // 如果是叶子节点或区域太小，直接返回
        if node.isLeaf || bounds.width < configuration.minimumSize || bounds.height < configuration.minimumSize {
            return true
        }
        
        // 准备子节点数据
        let children = prepareChildrenForLayout(node.children)
        guard !children.isEmpty else { return true }
        
        // 计算可用区域（减去间距）
        let availableBounds = bounds.insetBy(
            dx: configuration.spacing,
            dy: configuration.spacing
        )
        
        // 使用 Squarified Treemap 算法布局子节点
        return layoutChildrenUsingSquarify(
            children: children,
            in: availableBounds,
            depth: depth + 1
        )
    }
    
    /// 准备子节点用于布局
    private func prepareChildrenForLayout(_ children: [TreeNode]) -> [TreeNode] {
        // 过滤掉大小为0的节点
        let validChildren = children.filter { $0.value > 0 }
        
        // 按大小降序排序
        return validChildren.sorted { $0.value > $1.value }
    }
    
    /// 使用 Squarified Treemap 算法布局子节点
    private func layoutChildrenUsingSquarify(
        children: [TreeNode],
        in bounds: CGRect,
        depth: Int
    ) -> Bool {
        
        guard !children.isEmpty else { return true }
        
        let totalValue = children.reduce(0) { $0 + $1.value }
        guard totalValue > 0 else { return true }
        
        var remainingChildren = children
        var remainingBounds = bounds
        
        while !remainingChildren.isEmpty {
            // 找到最佳的子集进行布局
            let (bestRow, newBounds) = findBestRow(
                from: remainingChildren,
                in: remainingBounds,
                totalValue: totalValue
            )
            
            // 布局当前行
            layoutRow(bestRow, in: getRowBounds(remainingBounds, for: bestRow.count))
            
            // 递归布局子节点
            if configuration.enableRecursiveLayout {
                for child in bestRow {
                    calculateLayoutRecursively(
                        node: child,
                        bounds: child.layoutRect,
                        depth: depth
                    )
                }
            }
            
            // 更新剩余区域和节点
            remainingChildren.removeFirst(bestRow.count)
            remainingBounds = newBounds
        }
        
        return true
    }
    
    /// 找到最佳的行布局
    private func findBestRow(
        from children: [TreeNode],
        in bounds: CGRect,
        totalValue: Double
    ) -> (row: [TreeNode], remainingBounds: CGRect) {
        
        let shorter = min(bounds.width, bounds.height)
        var bestRow: [TreeNode] = []
        var bestAspectRatio = Double.infinity
        
        for i in 1...children.count {
            let currentRow = Array(children.prefix(i))
            let rowValue = currentRow.reduce(0) { $0 + $1.value }
            let aspectRatio = calculateWorstAspectRatio(
                for: currentRow,
                rowValue: rowValue,
                shorter: Double(shorter)
            )
            
            if aspectRatio < bestAspectRatio {
                bestAspectRatio = aspectRatio
                bestRow = currentRow
            } else {
                // 长宽比开始变差，停止
                break
            }
        }
        
        // 如果没有找到好的行，至少取第一个
        if bestRow.isEmpty {
            bestRow = [children[0]]
        }
        
        let remainingBounds = calculateRemainingBounds(
            original: bounds,
            usedByRowCount: bestRow.count,
            children: children
        )
        
        return (bestRow, remainingBounds)
    }
    
    /// 计算最差长宽比
    private func calculateWorstAspectRatio(
        for row: [TreeNode],
        rowValue: Double,
        shorter: Double
    ) -> Double {
        
        guard !row.isEmpty && rowValue > 0 && shorter > 0 else {
            return Double.infinity
        }
        
        let maxValue = row.map { $0.value }.max() ?? 0
        let minValue = row.map { $0.value }.min() ?? 0
        
        guard minValue > 0 else { return Double.infinity }
        
        let rowArea = rowValue * shorter
        let rowLength = rowArea / shorter
        
        let worstAspectRatio = max(
            (shorter * shorter * maxValue) / (rowLength * rowLength),
            (rowLength * rowLength) / (shorter * shorter * minValue)
        )
        
        return worstAspectRatio * configuration.aspectRatioWeight
    }
    
    /// 获取行的布局区域
    private func getRowBounds(_ bounds: CGRect, for rowCount: Int) -> CGRect {
        // 简化实现：根据方向选择合适的区域
        let isVertical = bounds.height > bounds.width
        
        if isVertical {
            // 垂直布局：行占满宽度
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: bounds.height / CGFloat(rowCount)
            )
        } else {
            // 水平布局：行占满高度
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width / CGFloat(rowCount),
                height: bounds.height
            )
        }
    }
    
    /// 布局一行中的节点
    private func layoutRow(_ row: [TreeNode], in rowBounds: CGRect) {
        let totalValue = row.reduce(0) { $0 + $1.value }
        guard totalValue > 0 else { return }
        
        let isVertical = rowBounds.height > rowBounds.width
        var currentPosition: CGFloat = isVertical ? rowBounds.minY : rowBounds.minX
        
        for node in row {
            let ratio = node.value / totalValue
            
            let rect: CGRect
            if isVertical {
                let height = rowBounds.height * CGFloat(ratio)
                rect = CGRect(
                    x: rowBounds.minX,
                    y: currentPosition,
                    width: rowBounds.width,
                    height: height
                )
                currentPosition += height
            } else {
                let width = rowBounds.width * CGFloat(ratio)
                rect = CGRect(
                    x: currentPosition,
                    y: rowBounds.minY,
                    width: width,
                    height: rowBounds.height
                )
                currentPosition += width
            }
            
            node.setLayoutRect(rect)
        }
    }
    
    /// 计算剩余区域
    private func calculateRemainingBounds(
        original bounds: CGRect,
        usedByRowCount rowCount: Int,
        children: [TreeNode]
    ) -> CGRect {
        
        let isVertical = bounds.height > bounds.width
        let totalValue = children.reduce(0) { $0 + $1.value }
        let usedValue = children.prefix(rowCount).reduce(0) { $0 + $1.value }
        let usedRatio = totalValue > 0 ? usedValue / totalValue : 0
        
        if isVertical {
            let usedHeight = bounds.height * CGFloat(usedRatio)
            return CGRect(
                x: bounds.minX,
                y: bounds.minY + usedHeight,
                width: bounds.width,
                height: bounds.height - usedHeight
            )
        } else {
            let usedWidth = bounds.width * CGFloat(usedRatio)
            return CGRect(
                x: bounds.minX + usedWidth,
                y: bounds.minY,
                width: bounds.width - usedWidth,
                height: bounds.height
            )
        }
    }
}

// MARK: - Layout Utilities

extension TreeMapLayoutCalculator {
    
    /// 获取指定点处的节点
    /// - Parameters:
    ///   - point: 查询点
    ///   - rootNode: 根节点
    /// - Returns: 包含该点的最深层节点
    static func findNode(at point: CGPoint, in rootNode: TreeNode) -> TreeNode? {
        return findNodeRecursively(at: point, in: rootNode)
    }
    
    private static func findNodeRecursively(at point: CGPoint, in node: TreeNode) -> TreeNode? {
        // 检查点是否在当前节点内
        guard node.layoutRect.contains(point) else {
            return nil
        }
        
        // 检查子节点
        for child in node.children {
            if let foundNode = findNodeRecursively(at: point, in: child) {
                return foundNode
            }
        }
        
        // 如果没有子节点包含该点，返回当前节点
        return node
    }
    
    /// 计算布局质量评分
    /// - Parameter rootNode: 根节点
    /// - Returns: 质量评分 (0.0 - 1.0，越高越好)
    static func calculateLayoutQuality(for rootNode: TreeNode) -> Double {
        var totalAspectRatio = 0.0
        var nodeCount = 0
        
        rootNode.preorderTraversal { node in
            guard node.isLayoutCalculated else { return }
            
            let rect = node.layoutRect
            let aspectRatio = max(rect.width, rect.height) / min(rect.width, rect.height)
            totalAspectRatio += Double(aspectRatio)
            nodeCount += 1
        }
        
        guard nodeCount > 0 else { return 0.0 }
        
        let averageAspectRatio = totalAspectRatio / Double(nodeCount)
        // 理想长宽比是1.0，评分与偏差成反比
        return max(0.0, 1.0 - (averageAspectRatio - 1.0) / 10.0)
    }
}
