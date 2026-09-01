// GlassBackground.swift — 液态玻璃背景（macOS 26 Liquid Glass）+ 旧系统回退
import SwiftUI

// MARK: - 液态玻璃背景
/// 统一封装面板背景：macOS 26+ 用 Liquid Glass 的 `glassEffect`，
/// 旧系统回退到 `ultraThinMaterial`。渐进式接入，保持 15.5 部署目标。
extension View {
    /// 应用液态玻璃背景。
    /// - Parameter cornerRadius: 面板圆角，0 表示直角（默认）。
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat = 0) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            background(.ultraThinMaterial)
        }
    }
}
