// StatsBarView.swift — 统计条视图 + 指标块
import SwiftUI

struct StatsBarView: View {
    let totalSize: Int64
    let fileCount: Int
    let folderCount: Int
    let isScanning: Bool
    let onChooseFolder: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            MetricBlock(
                icon: "externaldrive.fill",
                value: Double(totalSize),
                formatter: { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                label: "总大小"
            )
            MetricBlock(
                icon: "doc.fill",
                value: Double(fileCount),
                formatter: { "\(Int($0))" },
                label: "文件"
            )
            MetricBlock(
                icon: "folder.fill",
                value: Double(folderCount),
                formatter: { "\(Int($0))" },
                label: "文件夹"
            )
            Spacer()

            Button {
                onChooseFolder()
            } label: {
                Label("选择文件夹", systemImage: "folder.badge.plus")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isScanning)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .glassBackground()
    }
}

struct MetricBlock: View {
    let icon: String
    let value: Double
    let formatter: (Double) -> String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(formatter(value))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .contentTransition(.numericText(value: value))
                    .animation(.easeOut(duration: 0.3), value: value)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
