// BottomDetailBarView.swift — 底部紧凑详情条（名称/大小/类型/路径 + 操作）
import SwiftUI
import AppKit

// MARK: - 底部紧凑详情条
/// 单条横向展示选中/悬停项的概要信息与操作。
/// 显示优先级：悬停预览 > 点击选中。
/// 固定高度：内容变化（悬停/选中切换）不改变自身高度，避免连带触发
/// 地图区 GeometryReader 的 size 变化而重算布局。
struct BottomDetailBarView: View {
    let node: TreeNode?
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let node {
                Image(systemName: node.item.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundColor(node.item.isDirectory ? ColorSchemeManager.shared.colorForDirectory() : .secondary)

                Text(node.item.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Text(node.item.isDirectory ? "文件夹" : "文件")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(Radius.swatch)

                boundaryBadge(for: node)

                Text(node.item.path.path)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                Button("在Finder中显示") {
                    NSWorkspace.shared.selectFile(
                        node.item.path.path,
                        inFileViewerRootedAtPath: ""
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if node.item.isDirectory {
                    Button("重新扫描") {
                        fileSystemService.scanDirectory(at: node.item.path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button {
                    onRequestDelete(node)
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            } else {
                Text("悬停或点击矩形查看详情")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal)
        .frame(height: 48)
        .glassBackground()
    }

    /// 扫描边界角标：跨卷/符号链接/已计入
    @ViewBuilder
    private func boundaryBadge(for node: TreeNode) -> some View {
        switch node.scanBoundary {
        case .crossVolume:
            Label("跨卷", systemImage: "externaldrive")
                .font(.callout)
                .foregroundColor(.orange)
        case .symlink:
            Label("符号链接", systemImage: "link")
                .font(.callout)
                .foregroundColor(.secondary)
        case .alreadyCounted:
            Label("已计入", systemImage: "arrow.triangle.branch")
                .font(.callout)
                .foregroundColor(.secondary)
        case .normal:
            EmptyView()
        }
    }
}
