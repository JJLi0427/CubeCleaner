// GlassBackground.swift — 液态玻璃背景（macOS 26 Liquid Glass）+ 旧系统回退
import SwiftUI

extension View {
    /// 应用液态玻璃背景：macOS 26+ 用 `glassEffect`，旧系统回退 `ultraThinMaterial`。
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
