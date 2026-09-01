// TypeLegendStripView.swift — 横向类型分布图例条（chip 形式，位于比例条下方）
import SwiftUI

// MARK: - 横向类型分布图例条
/// 按类型横向排布的 chip，点击高亮对应类型。
/// 位于 StatsBarView 与 TypeRatioBarView 之下、TreeMap 之上。
struct TypeLegendStripView: View {
    let entries: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries.filter { $0.size > 0 }) { entry in
                    LegendChip(
                        entry: entry,
                        isHighlighted: highlightedFileType == entry.type
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleHighlight(entry.type) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - 图例 chip（色块 + 名称 + 占比）
struct LegendChip: View {
    let entry: ColorSchemeManager.TypeBreakdownEntry
    let isHighlighted: Bool

    var body: some View {
        let pct = entry.total > 0 ? Int(Double(entry.size) / Double(entry.total) * 100) : 0
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: Radius.swatch)
                .fill(entry.color)
                .frame(width: 14, height: 14)
            Text(entry.type.displayName)
                .font(.callout)
                .foregroundColor(.primary)
            Text("\(pct)%")
                .font(.callout)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isHighlighted
                ? Color.accentColor.opacity(0.18)
                : Color.primary.opacity(0.06)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row)
                .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(Radius.row)
        .help("\(entry.type.displayName) \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))")
    }
}
