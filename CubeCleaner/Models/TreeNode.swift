// TreeNode.swift — 树形结构节点模型

import Foundation

/// 文件系统的树形结构节点。
///
/// 普通 class（非 ObservableObject）：树节点不被 SwiftUI 单独观察，
/// 整棵树刷新由 FileSystemService.rootNode 一次性驱动，避免每个节点的 Combine 开销。
class TreeNode: Identifiable, Equatable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    var children: [TreeNode] = []

    private(set) var isAggregated: Bool = false

    /// 扫描边界：普通 / 跨挂载点 / 符号链接 / 已计入。
    /// 除 `.normal` 外都作为叶子渲染、不参与递归二分（见 BinaryTreeMapCalculator）。
    enum ScanBoundary: String {
        case normal
        case crossVolume      // 子目录是另一个卷的挂载点，跨卷未计入
        case symlink          // 符号链接，未跟随
        case alreadyCounted   // 硬链接/firmlink 目标，已在别处计入
    }
    private(set) var scanBoundary: ScanBoundary = .normal

    /// 缓存聚合大小（含所有子项），扫描建树后由 computeTotalSize() 自底向上填充一次。
    private(set) var totalSize: Int64

    func markAsAggregated() {
        isAggregated = true
    }

    func markScanBoundary(_ boundary: ScanBoundary) {
        scanBoundary = boundary
    }

    init(item: FileSystemItem, parent: TreeNode? = nil) {
        self.item = item
        self.parent = parent
        self.totalSize = item.size
    }

    func addChild(_ child: TreeNode) {
        children.append(child)
    }

    /// 自底向上计算并缓存子树聚合大小。
    /// 聚合节点不累加其 children（面积守恒，children 仅是挂载的小文件引用）。
    @discardableResult
    func computeTotalSize() -> Int64 {
        if isAggregated {
            return totalSize
        }
        if item.isDirectory {
            var sum: Int64 = 0
            for child in children {
                sum += child.computeTotalSize()
            }
            totalSize = item.size + sum
        } else {
            totalSize = item.size
        }
        return totalSize
    }

    func sortChildren(by comparison: (TreeNode, TreeNode) -> Bool) {
        children.sort(by: comparison)
        children.forEach { $0.sortChildren(by: comparison) }
    }

    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        return lhs.id == rhs.id
    }
}
