// NavigationBarView.swift — 导航条视图（返回按钮 + 面包屑）
import SwiftUI

struct NavigationBarView: View {
    let currentRoot: TreeNode?
    let rootNode: TreeNode?
    let onBack: () -> Void
    let onSelectBreadcrumb: (TreeNode) -> Void

    /// 是否在根目录（返回按钮禁用条件）
    private var isAtRoot: Bool {
        currentRoot == nil || currentRoot?.id == rootNode?.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("返回上一级", systemImage: "chevron.backward")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isAtRoot)

            Divider()
                .frame(height: 24)

            BreadcrumbView(currentRoot: currentRoot, onSelect: onSelectBreadcrumb)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .glassBackground()
    }
}
