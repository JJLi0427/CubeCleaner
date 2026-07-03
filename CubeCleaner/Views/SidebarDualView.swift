// SidebarDualView.swift — 侧栏上下堆叠两区（图例上、详情下）
import SwiftUI

// MARK: - 侧栏上下堆叠两区（图例上、详情下，不分页）
struct SidebarDualView: View {
    let selectedNode: Binding<TreeNode?>
    let hoveredNode: TreeNode?
    let typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 上半：图例区（弹性高度，可滚动）
            LegendSidebarView(
                entries: typeBreakdown,
                highlightedFileType: highlightedFileType,
                onToggleHighlight: onToggleHighlight
            )
            .frame(maxHeight: .infinity)
            Divider()
            // 下半：详情区（按内容，可滚动）
            DetailsSidebarView(
                selectedNode: selectedNode,
                hoveredNode: hoveredNode,
                fileSystemService: fileSystemService,
                scanRootURL: scanRootURL,
                onRequestDelete: onRequestDelete
            )
            .frame(minHeight: 240)
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }
}
