// TypeRatioBarView.swift — 类型占比比例条
import SwiftUI

struct TypeRatioBarView: View {
    let entries: [ColorSchemeManager.TypeBreakdownEntry]
    let isScanning: Bool

    @State private var animatedEntries: [ColorSchemeManager.TypeBreakdownEntry] = []

    /// 用大小数组作为 Equatable 变化键（TypeBreakdownEntry 未声明 Equatable）
    private var sizesKey: [Int64] { entries.map { $0.size } }

    var body: some View {
        if isScanning {
            ProgressView()
                .progressViewStyle(.linear)
                .frame(height: 10)
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    HStack(spacing: 0) {
                        ForEach(animatedEntries.filter { $0.size > 0 }) { entry in
                            entry.color
                                .frame(width: geo.size.width * entry.ratio)
                        }
                    }
                    .clipShape(Capsule())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sizesKey)
                }
            }
            .frame(height: 10)
            .help(tooltipText)
            .onAppear { animatedEntries = entries }
            .onChange(of: sizesKey) { _, _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    animatedEntries = entries
                }
            }
        }
    }

    /// 整条 tooltip（首版不分区段命中）
    private var tooltipText: String {
        guard !entries.isEmpty else { return "无数据" }
        let total = entries.first?.total ?? 0
        return entries
            .filter { $0.size > 0 }
            .map { e in
                let pct = total > 0 ? Int(Double(e.size) / Double(total) * 100) : 0
                return "\(e.type.displayName) \(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) \(pct)%"
            }
            .joined(separator: "\n")
    }
}
