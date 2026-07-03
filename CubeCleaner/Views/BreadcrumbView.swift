// BreadcrumbView.swift — 面包屑导航视图
import SwiftUI

// MARK: - 面包屑导航视图
struct BreadcrumbView: View {
    let currentRoot: TreeNode?
    let onSelect: (TreeNode) -> Void

    /// 从扫描根到 currentRoot 的路径
    private var path: [TreeNode] {
        var nodes: [TreeNode] = []
        var current: TreeNode? = currentRoot
        while let node = current {
            nodes.insert(node, at: 0)
            current = node.parent
        }
        return nodes
    }

    var body: some View {
        let crumbs = path
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { onSelect(node) }) {
                        Text(node.item.name)
                            .font(.caption)
                            .foregroundColor(index == crumbs.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .push(from: .leading),
                        removal: .push(from: .trailing)
                    ))
                }
            }
            .padding(.horizontal)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: crumbs)
        }
    }
}
