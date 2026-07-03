// LegendSidebarView.swift — 图例侧栏视图 + 图例行
import SwiftUI

// MARK: - 图例侧栏视图
struct LegendSidebarView: View {
    let entries: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("类型分布")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(entries.filter { $0.size > 0 }) { entry in
                        LegendRow(
                            entry: entry,
                            isHighlighted: highlightedFileType == entry.type
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onToggleHighlight(entry.type) }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(.regularMaterial)
    }
}

struct LegendRow: View {
    let entry: ColorSchemeManager.TypeBreakdownEntry
    let isHighlighted: Bool

    var body: some View {
        let pct = entry.total > 0 ? Int(Double(entry.size) / Double(entry.total) * 100) : 0
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: Radius.swatch)
                .fill(entry.color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.swatch)
                        .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            Text(entry.type.displayName)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text("\(pct)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(Radius.row)
        .shadow(color: isHighlighted ? Color.black.opacity(0.08) : Color.clear, radius: 3, x: 0, y: 1)
    }
}
