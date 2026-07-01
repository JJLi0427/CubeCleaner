//
//  ContentView.swift
//  CubeCleaner
//
//  Created by 李佳骏 on 2025/8/7.
//

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

struct ContentView: View {
    @StateObject private var fileSystemService = FileSystemService()
    @State private var layoutCalculator = BinaryTreeMapCalculator()
    @State private var rectangles: [TreeMapRectangle] = []
    @State private var selectedPath: URL?
    @State private var hoveredNode: TreeNode?
    @State private var selectedNode: TreeNode?
    @State private var currentRoot: TreeNode?
    @State private var showingFilePicker = false

    // v0.3: 图例侧栏 + 类型高亮 + 类型分布
    @State private var showLegend: Bool = true
    @State private var isAnimatingSidebar: Bool = false
    @State private var highlightedFileType: FileType? = nil
    @State private var typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry] = []

    // v0.3.1/v0.3.2: 侧栏双区 + 删除 + 钻取统计刷新 + 类型内深度配色
    @State private var scanRootURL: URL?
    @State private var showingDeleteConfirm = false
    @State private var subtreeTotalSize: Int64 = 0
    @State private var subtreeFileCount: Int = 0
    @State private var subtreeFolderCount: Int = 0

    // 性能优化相关状态
    @State private var isResizing = false
    @State private var layoutTask: Task<Void, Never>?
    @State private var resizeTimer: Timer?
    @State private var isLayouting = false

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button("选择文件夹") {
                    showingFilePicker = true
                }
                .disabled(fileSystemService.isScanning)
                .buttonStyle(.borderedProminent)

                if fileSystemService.isScanning {
                    Spacer()

                    Button("取消扫描") {
                        fileSystemService.cancelScan()
                    }
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let selectedPath = selectedPath {
                    Text("已选择: \(selectedPath.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Button {
                    isAnimatingSidebar = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showLegend.toggle()
                    }
                } label: {
                    Image(systemName: showLegend ? "sidebar.left" : "sidebar.right")
                }
                .buttonStyle(.bordered)
                .help(showLegend ? "隐藏类型图例" : "显示类型图例")
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // 统计条 + 类型比例条
            if fileSystemService.rootNode != nil || fileSystemService.isScanning {
                StatsBarView(
                    totalSize: subtreeTotalSize,
                    fileCount: subtreeFileCount,
                    folderCount: subtreeFolderCount,
                    isScanning: fileSystemService.isScanning
                )
                TypeRatioBarView(entries: typeBreakdown, isScanning: fileSystemService.isScanning)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                Divider()
            }

            // 主内容区域：Canvas + 图例侧栏
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ZStack {
                        Color(.controlBackgroundColor)

                    // 导航条（返回按钮 + 面包屑）- 浮于 TreeMap 顶部
                    VStack(spacing: 0) {
                        NavigationBarView(
                            currentRoot: currentRoot,
                            rootNode: fileSystemService.rootNode,
                            onBack: {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    currentRoot = currentRoot?.parent
                                }
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            },
                            onSelectBreadcrumb: { node in
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    currentRoot = node
                                }
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            }
                        )
                        Spacer()
                    }
                    .zIndex(1)

                    if rectangles.isEmpty && !fileSystemService.isScanning && !isResizing
                        && !isLayouting
                    {
                        // 空状态界面
                        EmptyStateView()
                    } else if !rectangles.isEmpty && !isResizing {
                        // TreeMap可视化 - 使用Canvas避免层级问题
                        TreeMapCanvasView(
                            rectangles: rectangles,
                            highlightedFileType: highlightedFileType,
                            selectedNode: selectedNode,
                            currentRoot: currentRoot ?? fileSystemService.rootNode,
                            onTap: { rectangle in
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    selectedNode = rectangle.node
                                }
                            },
                            onLongPress: { rectangle in
                                NSWorkspace.shared.selectFile(
                                    rectangle.node.item.path.path,
                                    inFileViewerRootedAtPath: ""
                                )
                            },
                            onDoubleTap: { rectangle in
                                // 目录可双击进入；聚合的"其他"块也可双击钻取内部小文件
                                let node = rectangle.node
                                if node.isAggregated || node.item.isDirectory {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                        currentRoot = node
                                    }
                                    Task {
                                        await updateLayoutOptimized(size: geometry.size)
                                    }
                                }
                            },
                            onHover: { rect in
                                hoveredNode = rect?.node
                            }
                        )
                        .clipped()
                    } else if fileSystemService.isScanning {
                        // 扫描状态
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)

                            Text("正在扫描文件系统...")
                                .font(.title2)
                                .foregroundColor(.primary)

                            ProgressView(value: fileSystemService.scanProgress)
                                .frame(width: 300)

                            VStack(spacing: 4) {
                                Text(
                                    "总大小: \(ByteCountFormatter.string(fromByteCount: fileSystemService.totalSize, countStyle: .file))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)

                                if !fileSystemService.currentPath.isEmpty {
                                    Text("当前: \(fileSystemService.currentPath)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 500)
                                        .animation(.easeInOut(duration: 0.15), value: fileSystemService.currentPath)
                                }
                            }

                            Button("取消扫描") {
                                fileSystemService.cancelScan()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if isResizing {
                        // 窗口大小调整时显示占位符
                        VStack(spacing: 16) {
                            Image(systemName: "rectangle.expand.vertical")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("调整窗口大小中...")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    } else if isLayouting {
                        // 布局计算中显示加载状态
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("计算布局中...")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .transition(.opacity)
                        }
                    }
                    }  // close ZStack

                    // 侧栏（图例上/详情下双区）
                    if showLegend {
                        SidebarDualView(
                            selectedNode: $selectedNode,
                            hoveredNode: hoveredNode,
                            typeBreakdown: typeBreakdown,
                            highlightedFileType: highlightedFileType,
                            onToggleHighlight: { type in
                                highlightedFileType = (highlightedFileType == type) ? nil : type
                            },
                            fileSystemService: fileSystemService,
                            scanRootURL: scanRootURL,
                            onRequestDelete: { _ in
                                showingDeleteConfirm = true
                            }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }  // close HStack
                .onAppear {
                    Task {
                        await updateLayoutOptimized(size: geometry.size)
                    }
                }
                .onChange(of: geometry.size) { _, newSize in
                    handleGeometryChange(newSize: newSize)
                }
                .onChange(of: fileSystemService.rootNode) { _, newNode in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        currentRoot = newNode
                    }
                    Task {
                        await updateLayoutOptimized(size: geometry.size)
                    }
                }
            }

            // 状态栏（统计已上移顶部，此处仅留错误/就绪/版本）
            HStack {
                if let errorMessage = fileSystemService.errorMessage {
                    Text("错误: \(errorMessage)")
                        .foregroundColor(.red)
                    Spacer()
                } else if fileSystemService.rootNode == nil {
                    Text("就绪")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Spacer()
                }
                Text("CubeCleaner v0.3.1")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
        .confirmationDialog(
            "移到废纸篓",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                if let node = selectedNode {
                    fileSystemService.trashAndRescan(
                        deleteURL: node.item.path,
                        scanRootURL: scanRootURL
                    )
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedNode = nil
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let node = selectedNode {
                Text("将把「\(node.item.name)」（\(ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file))）移到废纸篓，可在废纸篓中恢复。确定继续？")
            } else {
                Text("将把选中项移到废纸篓，可在废纸篓中恢复。确定继续？")
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedPath = url
                    scanRootURL = url
                    fileSystemService.scanDirectory(at: url)
                }
            case .failure(let error):
                print("文件选择失败: \(error)")
                fileSystemService.errorMessage = "文件选择失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 性能优化的布局更新方法

    /**
     * 处理窗口大小变化 - 实现resize时清除内容的逻辑
     */
    private func handleGeometryChange(newSize: CGSize) {
        // 取消之前的任务
        layoutTask?.cancel()
        resizeTimer?.invalidate()

        // 侧栏显隐驱动的尺寸变化不清空矩形（动画期间），仅等停手后重算
        if isAnimatingSidebar {
            isAnimatingSidebar = false
        } else if !isResizing {
            isResizing = true
            rectangles = []  // 清除所有矩形
        }

        // 设置延迟重新计算，等待用户停止拖动
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { @MainActor in
                isResizing = false
                await updateLayoutOptimized(size: newSize)
            }
        }
    }

    /**
     * 优化的异步布局更新方法
     */
    private func updateLayoutOptimized(size: CGSize) async {
        guard let rootNode = currentRoot ?? fileSystemService.rootNode,
            size.width > 0,
            size.height > 0
        else {
            rectangles = []
            return
        }

        // 取消之前的布局任务
        layoutTask?.cancel()

        // 显示布局计算状态
        withAnimation(.easeOut(duration: 0.2)) {
            isLayouting = true
        }

        // 异步计算布局
        layoutTask = Task { @MainActor in
            // 在后台线程计算布局
            let calculator = layoutCalculator
            let newRectangles = await Task.detached { [rootNode] in
                let rect = CGRect(origin: .zero, size: size)
                return calculator.calculateLayout(for: rootNode, in: rect)
            }.value

            // 检查任务是否被取消
            guard !Task.isCancelled else { return }

            // 在主线程更新UI
            withAnimation(.easeOut(duration: 0.3)) {
                rectangles = newRectangles
                isLayouting = false
                typeBreakdown = ColorSchemeManager.shared.typeBreakdown(for: rootNode)
                subtreeTotalSize = rootNode.totalSize
                subtreeFileCount = ColorSchemeManager.shared.fileCountInSubtree(rootNode)
                subtreeFolderCount = ColorSchemeManager.shared.folderCountInSubtree(rootNode)
            }
        }

        // 等待布局任务完成
        await layoutTask?.value
    }

    // 兼容旧接口的同步方法
    private func updateLayout(size: CGSize) {
        Task {
            await updateLayoutOptimized(size: size)
        }
    }
}

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
                    // 绘制所有矩形 - 一次性完成，没有层级问题
                    for rectangle in rectangles {
                        drawRectangle(context: context, rectangle: rectangle, dimProgress: progress)
                    }
                }
            }

            // 悬停发光浮层（Canvas 命令式绘制无法直接动画透明度，用 SwiftUI 浮层）
            if let hov = hoveredRectangle {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: hov.rect.width, height: hov.rect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )
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

        // 绘制边框 - 分层：当前视野顶层子(不同子文件夹/独立文件边界)粗深，
        // 文件夹内部块细。顶层子 = node.parent 是 currentRoot（或扫描根）。
        let parent = rectangle.node.parent
        let isTopLevelChild = parent?.id == currentRoot?.id
        let lineWidth: CGFloat
        let strokeOpacity: Double
        if isTopLevelChild {
            // 当前目录下不同文件夹/文件的分割线
            lineWidth = rectangle.isImportant ? 2.5 : 2.0
            strokeOpacity = 0.55
        } else {
            // 文件夹内部块边界
            lineWidth = rectangle.isImportant ? 1.2 : 0.8
            strokeOpacity = 0.25
        }
        context.stroke(
            Path(rect),
            with: .color(.primary.opacity(strokeOpacity)),
            lineWidth: lineWidth
        )

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
}

// MARK: - 详情侧栏视图（原中间浮层，改为侧栏页）
struct DetailsSidebarView: View {
    @Binding var selectedNode: TreeNode?
    let hoveredNode: TreeNode?
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    /// 显示优先级：悬停预览 > 点击选中。移开回落到选中（无则空态）。
    private var displayNode: TreeNode? { hoveredNode ?? selectedNode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let node = displayNode {
                    Group {
                        Text(node.item.name)
                            .font(.title3)
                            .fontWeight(.medium)

                        Text(
                            "大小: \(ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file))"
                        )
                        .font(.body)

                        Text("类型: \(node.item.isDirectory ? "文件夹" : "文件")")
                            .font(.body)

                        Text("路径:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(node.item.path.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if node.item.isDirectory && !node.children.isEmpty {
                            ChildrenListView(
                                selectedNode: node,
                                onSelectChild: { child in
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        self.selectedNode = child
                                    }
                                })
                        }

                        ActionsView(
                            selectedNode: node,
                            fileSystemService: fileSystemService,
                            scanRootURL: scanRootURL,
                            onDelete: { onRequestDelete(node) }
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    Text("悬停或点击矩形查看详情")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .id(displayNode?.id)
            .shadow(color: displayNode != nil ? ShadowSpec.card.color : Color.clear,
                    radius: displayNode != nil ? ShadowSpec.card.radius : 0,
                    x: ShadowSpec.card.x, y: ShadowSpec.card.y)
        }
    }
}

// MARK: - 子项目列表视图
struct ChildrenListView: View {
    let selectedNode: TreeNode
    let onSelectChild: (TreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("子项目 (\(selectedNode.children.count))")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(selectedNode.children.prefix(50), id: \.item.path) { child in
                        HStack {
                            Image(systemName: child.item.isDirectory ? "folder" : "doc")
                                .foregroundColor(child.item.isDirectory ? .blue : .gray)

                            Text(child.item.name)
                                .lineLimit(1)

                            Spacer()

                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: child.totalSize, countStyle: .file)
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 1)
                        .onTapGesture {
                            onSelectChild(child)
                        }
                    }

                    if selectedNode.children.count > 50 {
                        Text("还有 \(selectedNode.children.count - 50) 个项目...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }
}

// MARK: - 操作按钮视图
struct ActionsView: View {
    let selectedNode: TreeNode
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button("在Finder中显示") {
                NSWorkspace.shared.selectFile(
                    selectedNode.item.path.path,
                    inFileViewerRootedAtPath: ""
                )
            }
            .buttonStyle(.borderedProminent)

            Button {
                onDelete()
            } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if selectedNode.item.isDirectory {
                Button("重新扫描此文件夹") {
                    fileSystemService.scanDirectory(at: selectedNode.item.path)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - 面包屑导航视图
struct BreadcrumbView: View {
    let currentRoot: TreeNode?
    let onSelect: (TreeNode) -> Void

    /// 从扫描根到 currentRoot 的路径
    private var path: [TreeNode] {
        var nodes: [TreeNode] = []
        var current: TreeNode? = currentRoot
        while let node = current {
            nodes.insert(node, at: 0)
            current = node.parent
        }
        return nodes
    }

    var body: some View {
        let crumbs = path
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { onSelect(node) }) {
                        Text(node.item.name)
                            .font(.caption)
                            .foregroundColor(index == crumbs.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .push(from: .leading),
                        removal: .push(from: .trailing)
                    ))
                }
            }
            .padding(.horizontal)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: crumbs)
        }
    }
}

// MARK: - 统计条视图
struct StatsBarView: View {
    let totalSize: Int64
    let fileCount: Int
    let folderCount: Int
    let isScanning: Bool

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
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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

// MARK: - 类型占比比例条
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

// MARK: - 导航条视图（返回按钮 + 面包屑）
struct NavigationBarView: View {
    let currentRoot: TreeNode?
    let rootNode: TreeNode?
    let onBack: () -> Void
    let onSelectBreadcrumb: (TreeNode) -> Void

    /// 是否在根目录（返回按钮禁用条件）
    private var isAtRoot: Bool {
        currentRoot == nil || currentRoot?.id == rootNode?.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("返回上一级", systemImage: "chevron.backward")
            }
            .buttonStyle(.bordered)
            .disabled(isAtRoot)

            Divider()
                .frame(height: 16)

            BreadcrumbView(currentRoot: currentRoot, onSelect: onSelectBreadcrumb)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 侧栏上下堆叠两区（图例上、详情下，不分页）
struct SidebarDualView: View {
    let selectedNode: Binding<TreeNode?>
    let hoveredNode: TreeNode?
    let typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 上半：图例区（弹性高度，可滚动）
            LegendSidebarView(
                entries: typeBreakdown,
                highlightedFileType: highlightedFileType,
                onToggleHighlight: onToggleHighlight
            )
            .frame(maxHeight: .infinity)
            Divider()
            // 下半：详情区（按内容，可滚动）
            DetailsSidebarView(
                selectedNode: selectedNode,
                hoveredNode: hoveredNode,
                fileSystemService: fileSystemService,
                scanRootURL: scanRootURL,
                onRequestDelete: onRequestDelete
            )
            .frame(minHeight: 240)
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }
}

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

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
