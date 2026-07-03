// TreeNode.swift — 树形结构节点模型

import Combine
import Foundation

// MARK: TreeNode - 树形结构节点模型
/// 文件系统的树形结构节点
/// 支持递归遍历和层次化显示
///
/// 特性：
/// - ObservableObject: 支持SwiftUI数据绑定
/// - 父子关系维护
/// - 展开/折叠状态管理
/// - 递归大小计算
class TreeNode: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    @Published var children: [TreeNode] = []
    @Published var isExpanded: Bool = false

    /// 是否为聚合的虚拟"其他"节点
    private(set) var isAggregated: Bool = false

    /// 标记为聚合节点
    func markAsAggregated() {
        isAggregated = true
    }

    /// 节点在树中的层级深度
    var level: Int {
        (parent?.level ?? -1) + 1
    }

    /// 递归计算总大小（包含所有子项）
    var totalSize: Int64 {
        if item.isDirectory {
            return children.reduce(item.size) { $0 + $1.totalSize }
        }
        return item.size
    }

    init(item: FileSystemItem, parent: TreeNode? = nil) {
        self.item = item
        self.parent = parent
    }

    /// 添加子节点
    func addChild(_ child: TreeNode) {
        children.append(child)
    }

    /// 移除子节点
    func removeChild(_ child: TreeNode) {
        children.removeAll { $0.id == child.id }
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
