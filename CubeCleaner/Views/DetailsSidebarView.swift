// DetailsSidebarView.swift — 详情侧栏 + 子项列表 + 操作按钮
import SwiftUI
import AppKit

// MARK: - 详情侧栏视图（原中间浮层，改为侧栏页）
struct DetailsSidebarView: View {
    @Binding var selectedNode: TreeNode?
    let hoveredNode: TreeNode?
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    /// 显示优先级：悬停预览 > 点击选中。移开回落到选中（无则空态）。
    private var displayNode: TreeNode? { hoveredNode ?? selectedNode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let node = displayNode {
                    Group {
                        Text(node.item.name)
                            .font(.title3)
                            .fontWeight(.medium)

                        Text(
                            "大小: \(ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file))"
                        )
                        .font(.body)

                        Text("类型: \(node.item.isDirectory ? "文件夹" : "文件")")
                            .font(.body)

                        Text("路径:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(node.item.path.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if node.item.isDirectory && !node.children.isEmpty {
                            ChildrenListView(
                                selectedNode: node,
                                onSelectChild: { child in
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        self.selectedNode = child
                                    }
                                })
                        }

                        ActionsView(
                            selectedNode: node,
                            fileSystemService: fileSystemService,
                            scanRootURL: scanRootURL,
                            onDelete: { onRequestDelete(node) }
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    Text("悬停或点击矩形查看详情")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .id(displayNode?.id)
            .shadow(color: displayNode != nil ? ShadowSpec.card.color : Color.clear,
                    radius: displayNode != nil ? ShadowSpec.card.radius : 0,
                    x: ShadowSpec.card.x, y: ShadowSpec.card.y)
        }
    }
}

// MARK: - 子项目列表视图
struct ChildrenListView: View {
    let selectedNode: TreeNode
    let onSelectChild: (TreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("子项目 (\(selectedNode.children.count))")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(selectedNode.children.prefix(50), id: \.item.path) { child in
                        HStack {
                            Image(systemName: child.item.isDirectory ? "folder" : "doc")
                                .foregroundColor(child.item.isDirectory ? .blue : .gray)

                            Text(child.item.name)
                                .lineLimit(1)

                            Spacer()

                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: child.totalSize, countStyle: .file)
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 1)
                        .onTapGesture {
                            onSelectChild(child)
                        }
                    }

                    if selectedNode.children.count > 50 {
                        Text("还有 \(selectedNode.children.count - 50) 个项目...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }
}

// MARK: - 操作按钮视图
struct ActionsView: View {
    let selectedNode: TreeNode
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button("在Finder中显示") {
                NSWorkspace.shared.selectFile(
                    selectedNode.item.path.path,
                    inFileViewerRootedAtPath: ""
                )
            }
            .buttonStyle(.borderedProminent)

            Button {
                onDelete()
            } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if selectedNode.item.isDirectory {
                Button("重新扫描此文件夹") {
                    fileSystemService.scanDirectory(at: selectedNode.item.path)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
