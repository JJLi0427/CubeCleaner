// TreeNode.swift — 树形结构节点模型

import Foundation

// MARK: TreeNode - 树形结构节点模型
/// 文件系统的树形结构节点
/// 支持递归遍历和层次化显示
///
/// 特性：
/// - 父子关系维护
/// - 缓存聚合大小（扫描后自底向上一次计算，此后 O(1) 读取）
///
/// 普通 class（非 ObservableObject）：树节点不被 SwiftUI 单独观察，
/// 整棵树的刷新由 FileSystemService.rootNode 一次性驱动，避免每个节点的 Combine 开销。
class TreeNode: Identifiable, Equatable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    var children: [TreeNode] = []

    /// 是否为聚合的虚拟"其他"节点
    private(set) var isAggregated: Bool = false

    /// 扫描边界标记：普通 / 跨挂载点 / 符号链接 / 已计入(硬链接/firmlink 去重命中)。
    /// 除 `.normal` 外的节点都作为叶子渲染、不参与递归二分（见 BinaryTreeMapCalculator）。
    enum ScanBoundary: String {
        case normal
        case crossVolume      // 子目录是另一个卷的挂载点，跨卷未计入
        case symlink          // 符号链接，未跟随
        case alreadyCounted   // 硬链接/firmlink 目标，已在别处计入
    }
    private(set) var scanBoundary: ScanBoundary = .normal

    /// 缓存聚合大小（含所有子项）。扫描建树后由 computeTotalSize() 自底向上填充一次。
    /// 聚合"其他"块保持 item.size（其 children 不累加，面积守恒，见 BinaryTreeMapCalculator）。
    private(set) var totalSize: Int64

    /// 标记为聚合节点
    func markAsAggregated() {
        isAggregated = true
    }

    /// 标记扫描边界（跨卷/符号链接/已计入）。标记后不应再递归其子项。
    func markScanBoundary(_ boundary: ScanBoundary) {
        scanBoundary = boundary
    }

    init(item: FileSystemItem, parent: TreeNode? = nil) {
        self.item = item
        self.parent = parent
        self.totalSize = item.size
    }

    /// 添加子节点
    func addChild(_ child: TreeNode) {
        children.append(child)
    }

    /// 自底向上计算并缓存子树聚合大小。扫描建树完成后调用一次，返回本节点聚合大小。
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

    /// 递归排序子节点
    func sortChildren(by comparison: (TreeNode, TreeNode) -> Bool) {
        children.sort(by: comparison)
        children.forEach { $0.sortChildren(by: comparison) }
    }

    // MARK: - Equatable
    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        return lhs.id == rhs.id
    }
}
