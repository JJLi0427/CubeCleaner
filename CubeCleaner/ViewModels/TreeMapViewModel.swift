//
//  TreeMapViewModel.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation
import SwiftUI
import Combine

/// 树状图视图模型
/// 管理树状图的显示、交互和导航状态
@Observable
class TreeMapViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前显示的根节点
    @Published var currentRootNode: TreeNode?
    
    /// 选中的节点
    @Published var selectedNode: TreeNode?
    
    /// 悬停的节点
    @Published var hoveredNode: TreeNode?
    
    /// 可视区域大小
    @Published var viewportSize: CGSize = .zero
    
    /// 缩放级别
    @Published var zoomLevel: Double = 1.0
    
    /// 平移偏移
    @Published var panOffset: CGPoint = .zero
    
    /// 显示模式
    @Published var displayMode: DisplayMode = .size
    
    /// 颜色方案
    @Published var colorScheme: TreeMapColorScheme = .fileType
    
    /// 是否显示标签
    @Published var showLabels: Bool = true
    
    /// 标签显示阈值
    @Published var labelThreshold: CGFloat = 20.0
    
    /// 是否启用动画
    @Published var animationsEnabled: Bool = true
    
    /// 导航历史栈
    @Published var navigationHistory: [TreeNode] = []
    
    /// 当前导航位置
    @Published var currentNavigationIndex: Int = -1
    
    // MARK: - Private Properties
    
    private let layoutCalculator: TreeMapLayoutCalculator
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    /// 是否可以后退
    var canGoBack: Bool {
        return currentNavigationIndex > 0
    }
    
    /// 是否可以前进
    var canGoForward: Bool {
        return currentNavigationIndex < navigationHistory.count - 1
    }
    
    /// 是否可以上级导航
    var canGoUp: Bool {
        return currentRootNode?.parent != nil
    }
    
    /// 当前缩放级别是否允许放大
    var canZoomIn: Bool {
        return zoomLevel < 10.0
    }
    
    /// 当前缩放级别是否允许缩小
    var canZoomOut: Bool {
        return zoomLevel > 0.1
    }
    
    // MARK: - Initialization
    
    init(layoutCalculator: TreeMapLayoutCalculator = TreeMapLayoutCalculator()) {
        self.layoutCalculator = layoutCalculator
        setupBindings()
    }
    
    private func setupBindings() {
        // 监听视图大小变化，重新计算布局
        $viewportSize
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateLayout()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Interface
    
    /// 设置要显示的树数据
    /// - Parameter rootNode: 根节点
    func setTreeData(_ rootNode: TreeNode) {
        currentRootNode = rootNode
        selectedNode = nil
        hoveredNode = nil
        
        // 添加到导航历史
        addToNavigationHistory(rootNode)
        
        // 重新计算布局
        recalculateLayout()
    }
    
    /// 导航到指定节点
    /// - Parameter node: 目标节点
    func navigateTo(_ node: TreeNode) {
        guard node.isDirectory || !node.children.isEmpty else { return }
        
        currentRootNode = node
        selectedNode = nil
        hoveredNode = nil
        
        // 重置视图状态
        resetViewState()
        
        // 添加到导航历史
        addToNavigationHistory(node)
        
        // 重新计算布局
        recalculateLayout()
    }
    
    /// 后退导航
    func goBack() {
        guard canGoBack else { return }
        
        currentNavigationIndex -= 1
        let targetNode = navigationHistory[currentNavigationIndex]
        
        currentRootNode = targetNode
        selectedNode = nil
        hoveredNode = nil
        
        resetViewState()
        recalculateLayout()
    }
    
    /// 前进导航
    func goForward() {
        guard canGoForward else { return }
        
        currentNavigationIndex += 1
        let targetNode = navigationHistory[currentNavigationIndex]
        
        currentRootNode = targetNode
        selectedNode = nil
        hoveredNode = nil
        
        resetViewState()
        recalculateLayout()
    }
    
    /// 向上导航
    func goUp() {
        guard let parent = currentRootNode?.parent else { return }
        navigateTo(parent)
    }
    
    // MARK: - Layout Management
    
    /// 重新计算布局
    func recalculateLayout() {
        guard let rootNode = currentRootNode,
              viewportSize.width > 0,
              viewportSize.height > 0 else { return }
        
        let bounds = CGRect(origin: .zero, size: viewportSize)
        layoutCalculator.calculateLayout(for: rootNode, in: bounds)
    }
    
    /// 获取节点的显示矩形（考虑缩放和平移）
    /// - Parameter node: 目标节点
    /// - Returns: 变换后的矩形
    func getDisplayRect(for node: TreeNode) -> CGRect {
        let rect = node.layoutRect
        
        // 应用缩放
        let scaledRect = CGRect(
            x: rect.origin.x * zoomLevel,
            y: rect.origin.y * zoomLevel,
            width: rect.size.width * zoomLevel,
            height: rect.size.height * zoomLevel
        )
        
        // 应用平移
        return scaledRect.offsetBy(dx: panOffset.x, dy: panOffset.y)
    }
    
    // MARK: - Interaction Handling
    
    /// 处理点击事件
    /// - Parameter point: 点击位置
    func handleTap(at point: CGPoint) {
        let adjustedPoint = adjustPointForViewTransform(point)
        
        guard let rootNode = currentRootNode,
              let tappedNode = TreeMapLayoutCalculator.findNode(at: adjustedPoint, in: rootNode) else {
            selectedNode = nil
            return
        }
        
        if selectedNode?.id == tappedNode.id {
            // 双击效果：导航到选中节点
            if tappedNode.isDirectory && !tappedNode.children.isEmpty {
                navigateTo(tappedNode)
            }
        } else {
            selectedNode = tappedNode
        }
    }
    
    /// 处理悬停事件
    /// - Parameter point: 悬停位置
    func handleHover(at point: CGPoint?) {
        guard let point = point else {
            hoveredNode = nil
            return
        }
        
        let adjustedPoint = adjustPointForViewTransform(point)
        
        guard let rootNode = currentRootNode else {
            hoveredNode = nil
            return
        }
        
        hoveredNode = TreeMapLayoutCalculator.findNode(at: adjustedPoint, in: rootNode)
    }
    
    /// 处理缩放手势
    /// - Parameters:
    ///   - scale: 缩放倍数
    ///   - center: 缩放中心点
    func handleZoom(scale: Double, center: CGPoint) {
        let newZoomLevel = (zoomLevel * scale).clamped(to: 0.1...10.0)
        
        if newZoomLevel != zoomLevel {
            // 计算缩放时的平移调整
            let scaleDelta = newZoomLevel / zoomLevel
            let adjustedCenter = CGPoint(
                x: center.x - panOffset.x,
                y: center.y - panOffset.y
            )
            
            panOffset.x = center.x - adjustedCenter.x * scaleDelta
            panOffset.y = center.y - adjustedCenter.y * scaleDelta
            
            zoomLevel = newZoomLevel
        }
    }
    
    /// 处理平移手势
    /// - Parameter translation: 平移量
    func handlePan(translation: CGPoint) {
        panOffset.x += translation.x
        panOffset.y += translation.y
    }
    
    // MARK: - View Controls
    
    /// 缩放到适合
    func zoomToFit() {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        
        zoomLevel = 1.0
        panOffset = .zero
    }
    
    /// 放大
    func zoomIn() {
        zoomLevel = (zoomLevel * 1.5).clamped(to: 0.1...10.0)
    }
    
    /// 缩小
    func zoomOut() {
        zoomLevel = (zoomLevel / 1.5).clamped(to: 0.1...10.0)
    }
    
    /// 重置视图状态
    func resetViewState() {
        zoomLevel = 1.0
        panOffset = .zero
    }
    
    // MARK: - Display Configuration
    
    /// 设置显示模式
    /// - Parameter mode: 显示模式
    func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        recalculateLayout()
    }
    
    /// 设置颜色方案
    /// - Parameter scheme: 颜色方案
    func setColorScheme(_ scheme: TreeMapColorScheme) {
        colorScheme = scheme
    }
    
    /// 获取节点颜色
    /// - Parameter node: 目标节点
    /// - Returns: 节点颜色
    func getColor(for node: TreeNode) -> Color {
        return colorScheme.color(for: node)
    }
    
    /// 是否应该显示节点标签
    /// - Parameter node: 目标节点
    /// - Returns: 是否显示标签
    func shouldShowLabel(for node: TreeNode) -> Bool {
        guard showLabels else { return false }
        
        let displayRect = getDisplayRect(for: node)
        return min(displayRect.width, displayRect.height) >= labelThreshold
    }
    
    // MARK: - Private Methods
    
    private func addToNavigationHistory(_ node: TreeNode) {
        // 如果当前不在历史末尾，清除后续历史
        if currentNavigationIndex < navigationHistory.count - 1 {
            navigationHistory.removeSubrange((currentNavigationIndex + 1)...)
        }
        
        // 添加新节点
        navigationHistory.append(node)
        currentNavigationIndex = navigationHistory.count - 1
        
        // 限制历史记录长度
        if navigationHistory.count > 50 {
            navigationHistory.removeFirst()
            currentNavigationIndex -= 1
        }
    }
    
    private func adjustPointForViewTransform(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: (point.x - panOffset.x) / zoomLevel,
            y: (point.y - panOffset.y) / zoomLevel
        )
    }
}

// MARK: - Supporting Types

/// 显示模式
enum DisplayMode: String, CaseIterable {
    case size = "size"
    case count = "count"
    case modified = "modified"
    
    var displayName: String {
        switch self {
        case .size: return "按大小"
        case .count: return "按数量"
        case .modified: return "按修改时间"
        }
    }
}

/// 树状图颜色方案
enum TreeMapColorScheme: String, CaseIterable {
    case fileType = "fileType"
    case size = "size"
    case depth = "depth"
    case modified = "modified"
    
    var displayName: String {
        switch self {
        case .fileType: return "文件类型"
        case .size: return "文件大小"
        case .depth: return "目录深度"
        case .modified: return "修改时间"
        }
    }
    
    func color(for node: TreeNode) -> Color {
        switch self {
        case .fileType:
            return Color(hex: node.fileSystemItem.fileType.colorHex) ?? .gray
        case .size:
            return sizeBasedColor(for: node)
        case .depth:
            return depthBasedColor(for: node)
        case .modified:
            return modificationBasedColor(for: node)
        }
    }
    
    private func sizeBasedColor(for node: TreeNode) -> Color {
        let size = node.fileSystemItem.totalSize
        let gb = Int64(1024 * 1024 * 1024)
        let mb = Int64(1024 * 1024)
        
        if size > gb {
            return .red
        } else if size > 100 * mb {
            return .orange
        } else if size > 10 * mb {
            return .yellow
        } else if size > mb {
            return .green
        } else {
            return .blue
        }
    }
    
    private func depthBasedColor(for node: TreeNode) -> Color {
        let depth = node.depth
        let hue = Double(depth % 6) / 6.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
    
    private func modificationBasedColor(for node: TreeNode) -> Color {
        guard let modDate = node.fileSystemItem.modificationDate else {
            return .gray
        }
        
        let daysSinceModification = Date().timeIntervalSince(modDate) / (24 * 60 * 60)
        
        if daysSinceModification < 1 {
            return .red
        } else if daysSinceModification < 7 {
            return .orange
        } else if daysSinceModification < 30 {
            return .yellow
        } else if daysSinceModification < 365 {
            return .green
        } else {
            return .blue
        }
    }
}

// MARK: - Extensions

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
