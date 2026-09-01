// EmptyStateView.swift — 空状态视图（脉冲图标 + 材质卡）
import SwiftUI

// MARK: - 空状态视图（脉冲图标 + 材质卡）
struct EmptyStateView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .scaleEffect(pulse ? 1.05 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

            VStack(spacing: 8) {
                Text("选择一个文件夹开始扫描")
                    .font(.title2)
                    .foregroundColor(.primary)

                Text("点击上方的\"选择文件夹\"按钮开始分析磁盘使用情况")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 400)
        .padding(24)
        .glassBackground(cornerRadius: Radius.card)
    }
}
