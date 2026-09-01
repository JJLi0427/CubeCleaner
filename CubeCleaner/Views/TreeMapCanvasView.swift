// TreeMapCanvasView.swift — TreeMap Canvas 可视化视图（无层级问题）
import SwiftUI

// MARK: - TreeMap Canvas View (无层级问题的解决方案)
struct TreeMapCanvasView: View {
    let rectangles: [TreeMapRectangle]
    let highlightedFileType: FileType?
    let selectedNode: TreeNode?
    let currentRoot: TreeNode?
    let onTap: (TreeMapRectangle) -> Void
    let onLongPress: (TreeMapRectangle) -> Void
    let onDoubleTap: (TreeMapRectangle) -> Void
    let onHover: (TreeMapRectangle?) -> Void

    @State private var hoveredRectangle: TreeMapRectangle?
    // 高亮降透动画：dimProgress 0→1 插值，由 TimelineView 驱动
    @State private var dimAnimStart: Date?
    @State private var dimFrom: Double = 0
    @State private var dimTo: Double = 0

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let progress = computeDimProgress(now: timeline.date)
                Canvas { context, size in
                    // 绘制所有矩形
                    for rectangle in rectangles {
                        drawRectangle(context: context, rectangle: rectangle, dimProgress: progress)
                    }
                    // 顶层子(当前目录下的目录/独立文件)包络外框：把属于同一顶层子的
                    // 所有叶子块区域圈起来，目录用青色粗框、独立文件用主色框，一眼分组。
                    for group in groupBoundingBoxes() {
                        let framePath = Path(roundedRect: group.box.insetBy(dx: 1, dy: 1),
                                             cornerRadius: Radius.card)
                        context.stroke(
                            framePath,
                            with: .color(group.color),
                            lineWidth: 2.5
                        )
                    }
                }
            }

            // 悬停高亮浮层：macOS 26 用液态玻璃高亮（透出下方矩形颜色 + 玻璃边缘高光），
            // 旧系统回退为白色细描边。Canvas 命令式绘制无法直接动画透明度，用 SwiftUI 浮层。
            if let hov = hoveredRectangle {
                Group {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(Color.white.opacity(0.08))
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.card)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    }
                }
                .frame(width: hov.rect.width, height: hov.rect.height)
                .position(x: hov.rect.midX, y: hov.rect.midY)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // 选中描边浮层
            if let sel = selectedNode,
               let rect = rectangles.first(where: { $0.node.id == sel.id })?.rect {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .shadow(color: ShadowSpec.ring.color, radius: ShadowSpec.ring.radius)
                    )
                    .position(x: rect.midX, y: rect.midY)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            // 双击优先；若未触发双击则作为单击。避免单击打开详情浮层吞掉双击的第二下。
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    if let hitRectangle = findRectangleAt(value.location) {
                        onDoubleTap(hitRectangle)
                    }
                }
                .exclusively(before: SpatialTapGesture()
                    .onEnded { value in
                        if let hitRectangle = findRectangleAt(value.location) {
                            onTap(hitRectangle)
                        }
                    }
                )
        )
        .gesture(
            // 长按手势
            LongPressGesture(minimumDuration: 0.5)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { value in
                    switch value {
                    case .second(true, let drag):
                        if let location = drag?.location {
                            if let hitRectangle = findRectangleAt(location) {
                                onLongPress(hitRectangle)
                            }
                        }
                    default:
                        break
                    }
                }
        )
        .onContinuousHover { phase in
            // 复活悬停高亮：根据鼠标位置实时更新 hoveredRectangle
            switch phase {
            case .active(let location):
                let newHover = findRectangleAt(location)
                // 去重：仅当悬停目标真变时才更新+回调，避免高频抖动
                if hoveredRectangle?.id != newHover?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredRectangle = newHover
                    }
                    onHover(newHover)
                }
            case .ended:
                if hoveredRectangle != nil {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredRectangle = nil
                    }
                    onHover(nil)
                }
            }
        }
        .onChange(of: highlightedFileType) { _, newType in
            dimFrom = currentDimValue
            dimTo = (newType == nil) ? 0.0 : 1.0
            dimAnimStart = Date()
        }
        .onAppear {
            if highlightedFileType != nil {
                dimFrom = 0
                dimTo = 1
                dimAnimStart = Date()
            }
        }
    }

    /// 当前降透进度（0=无降透，1=完全降透）。无动画进行时返回 dimTo。
    private var currentDimValue: Double {
        guard let start = dimAnimStart else { return dimTo }
        let elapsed = Date().timeIntervalSince(start)
        let duration = 0.25
        if elapsed >= duration { return dimTo }
        let t = elapsed / duration
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        return dimFrom + (dimTo - dimFrom) * eased
    }

    /// TimelineView 每帧调用，计算当前降透进度
    private func computeDimProgress(now: Date) -> Double {
        guard let start = dimAnimStart else { return dimTo }
        let elapsed = now.timeIntervalSince(start)
        let duration = 0.25
        if elapsed >= duration { return dimTo }
        let t = elapsed / duration
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        return dimFrom + (dimTo - dimFrom) * eased
    }

    /// 当前矩形是否属于高亮类型（文件夹在存在高亮时视为不高亮）
    private func isHighlighted(_ rectangle: TreeMapRectangle) -> Bool {
        guard let highlightedFileType else { return true }
        if rectangle.node.item.isDirectory { return false }
        let ft = FileType.from(extension: rectangle.node.item.fileExtension)
        return ft == highlightedFileType
    }

    /**
     * 绘制单个矩形 - 直接Canvas绘制，无视图层级
     */
    private func drawRectangle(context: GraphicsContext, rectangle: TreeMapRectangle, dimProgress: Double) {
        let rect = rectangle.rect
        let isHovered = hoveredRectangle?.id == rectangle.id

        // 绘制背景 - 颜色深度由 depthColor 承载(亮度通道)，此处透明度用常量；
        // 高亮类型保持原色，其它按 dimProgress 降透（0=不降，1=降到 0.2）
        let dimmed = highlightedFileType != nil && !isHighlighted(rectangle)
        let baseOpacity: Double = isHovered ? 0.95 : 0.85
        let dimFactor = dimmed ? (1.0 - 0.8 * dimProgress) : 1.0
        let opacity = baseOpacity * dimFactor
        context.fill(
            Path(rect),
            with: .color(rectangle.color.opacity(opacity))
        )

        // 绘制边框 - 内部块统一细线；顶层子分组用包络外框(见 groupBoundingBoxes)表达。
        context.stroke(
            Path(rect),
            with: .color(.primary.opacity(0.18)),
            lineWidth: 0.5
        )

        // 扫描边界角标：跨卷/符号链接/已计入 各用不同 SF Symbol 标记，一眼区分。
        let boundary = rectangle.node.scanBoundary
        if boundary != .normal && rect.width > 28 && rect.height > 16 {
            let iconName: String
            switch boundary {
            case .crossVolume: iconName = "externaldrive"
            case .symlink: iconName = "link"
            case .alreadyCounted: iconName = "arrow.triangle.branch"
            case .normal: iconName = ""
            }
            if !iconName.isEmpty {
                // 用 Text 包裹 Image 以便 GraphicsContext.resolve 解析尺寸与颜色。
                let badge = Text(Image(systemName: iconName))
                    .font(.system(size: min(11, rect.height / 3)))
                    .foregroundColor(.secondary)
                let resolved = context.resolve(badge)
                let badgeSize = resolved.measure(in: rect.size)
                context.draw(
                    resolved,
                    at: CGPoint(
                        x: rect.maxX - badgeSize.width / 2 - 4,
                        y: rect.minY + badgeSize.height / 2 + 4
                    )
                )
            }
        }

        // 绘制文本 - 如果矩形足够大
        if rectangle.shouldShowLabel && !rectangle.displayName.isEmpty {
            let textRect = CGRect(
                x: rect.minX + 4,
                y: rect.minY + 4,
                width: rect.width - 8,
                height: rect.height - 8
            )

            if textRect.width > 0 && textRect.height > 0 {
                context.draw(
                    Text(rectangle.displayName)
                        .font(.system(size: min(11, rect.height / 4)))
                        .fontWeight(rectangle.isImportant ? .semibold : .medium)
                        .foregroundColor(.primary),
                    in: textRect
                )

                // 绘制大小信息
                if rectangle.canShowSize {
                    let sizeRect = CGRect(
                        x: rect.minX + 4,
                        y: rect.minY + rect.height / 4 + 8,
                        width: rect.width - 8,
                        height: rect.height / 6
                    )

                    if sizeRect.height > 0 {
                        context.draw(
                            Text(rectangle.formattedSize)
                                .font(.system(size: min(9, rect.height / 6)))
                                .foregroundColor(.secondary),
                            in: sizeRect
                        )
                    }
                }
            }
        }
    }

    /**
     * 点击位置检测 - 手动计算哪个矩形被点击
     * 这样就完全避免了视图层级问题
     */
    private func findRectangleAt(_ location: CGPoint) -> TreeMapRectangle? {
        // 从后往前遍历，模拟视觉上的"最上层"
        // 但实际上没有层级，只是逻辑上的优先级
        for rectangle in rectangles.reversed() {
            if rectangle.rect.contains(location) {
                return rectangle
            }
        }
        return nil
    }

    /// 顶层子分组包络框：每个"当前视野直接子项"(currentRoot 的直接子)把它名下所有
    /// 叶子块的区域算 union 包围框。目录用青色框、独立文件用主色框，一眼区分同级项。
    private struct GroupBox {
        let box: CGRect
        let color: Color
    }

    private func groupBoundingBoxes() -> [GroupBox] {
        guard let root = currentRoot else { return [] }

        // 沿 parent 上溯，找到 rect.node 所属的顶层子(其 parent 恰为 currentRoot)。
        func topLevelAncestor(of node: TreeNode) -> TreeNode? {
            var cur: TreeNode? = node
            while let n = cur {
                if n.parent?.id == root.id { return n }
                if n.id == root.id { return nil }  // 到根仍未命中
                cur = n.parent
            }
            return nil
        }

        // 按顶层子 id 聚合 union box + 记住该顶层子是否目录
        var boxes: [UUID: CGRect] = [:]
        var isDir: [UUID: Bool] = [:]
        for r in rectangles {
            guard let top = topLevelAncestor(of: r.node) else { continue }
            if let existing = boxes[top.id] {
                boxes[top.id] = existing.union(r.rect)
            } else {
                boxes[top.id] = r.rect
                isDir[top.id] = top.item.isDirectory
            }
        }

        let dirColor = ColorSchemeManager.shared.colorForDirectory()
        return boxes.map { id, box in
            GroupBox(
                box: box,
                color: (isDir[id] == true) ? dirColor : Color.primary.opacity(0.5)
            )
        }
    }
}
