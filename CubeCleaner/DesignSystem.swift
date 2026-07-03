// DesignSystem.swift — 设计系统常量（圆角/阴影规格）
import SwiftUI

// MARK: - 设计系统常量
enum Radius {
    static let swatch: CGFloat = 3
    static let row: CGFloat = 6
    static let card: CGFloat = 10
}

enum ShadowSpec {
    static let card = (color: Color.black.opacity(0.06), radius: 6.0, x: 0.0, y: 2.0)
    static let ring = (color: Color.accentColor.opacity(0.35), radius: 4.0, x: 0.0, y: 0.0)
}
