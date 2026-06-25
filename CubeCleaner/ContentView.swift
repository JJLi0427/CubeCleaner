//
//  ContentView.swift
//  CubeCleaner
//
//  Created by 李佳骏 on 2025/8/7.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var fileSystemService = FileSystemService()
    @State private var layoutCalculator = BinaryTreeMapCalculator()
    @State private var rectangles: [TreeMapRectangle] = []
    @State private var selectedPath: URL?
    @State private var hoveredNode: TreeNode?
    @State private var selectedNode: TreeNode?
    @State private var currentRoot: TreeNode?
    @State private var showingDetails = false
    @State private var showingFilePicker = false

    // v0.3: 图例侧栏 + 类型高亮 + 类型分布
    @State private var showLegend: Bool = true
    @State private var highlightedFileType: FileType? = nil
    @State private var typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry] = []

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
                    showLegend.toggle()
                } label: {
                    Image(systemName: showLegend ? "sidebar.left" : "sidebar.right")
                }
                .buttonStyle(.bordered)
                .help(showLegend ? "隐藏类型图例" : "显示类型图例")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 统计条 + 类型比例条
            if fileSystemService.rootNode != nil || fileSystemService.isScanning {
                StatsBarView(
                    totalSize: fileSystemService.totalSize,
                    fileCount: fileSystemService.filesScanned,
                    folderCount: fileSystemService.folderCount,
                    isScanning: fileSystemService.isScanning
                )
                TypeRatioBarView(entries: typeBreakdown, isScanning: fileSystemService.isScanning)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(Color(.controlBackgroundColor))
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
                                currentRoot = currentRoot?.parent
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            },
                            onSelectBreadcrumb: { node in
                                currentRoot = node
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
                        VStack(spacing: 16) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)

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
                    } else if !rectangles.isEmpty && !isResizing {
                        // TreeMap可视化 - 使用Canvas避免层级问题
                        TreeMapCanvasView(
                            rectangles: rectangles,
                            highlightedFileType: highlightedFileType,
                            onTap: { rectangle in
                                selectedNode = rectangle.node
                                showingDetails = true
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
                                    currentRoot = node
                                    Task {
                                        await updateLayoutOptimized(size: geometry.size)
                                    }
                                }
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
                        }
                    }

                    // 详情面板（浮于 Canvas 之上的覆盖层）
                    if showingDetails {
                        DetailsPanelView(
                            selectedNode: $selectedNode,
                            showingDetails: $showingDetails,
                            fileSystemService: fileSystemService
                        )
                    }
                    }  // close ZStack

                    // 图例侧栏
                    if showLegend {
                        LegendSidebarView(
                            entries: typeBreakdown,
                            highlightedFileType: highlightedFileType,
                            onToggleHighlight: { type in
                                highlightedFileType = (highlightedFileType == type) ? nil : type
                            }
                        )
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
                    currentRoot = newNode
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
                Text("CubeCleaner v0.3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
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

        // 立即清除内容，显示resize状态
        if !isResizing {
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
        isLayouting = true

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
            withAnimation(.easeOut(duration: 0.25)) {
                rectangles = newRectangles
                isLayouting = false
                typeBreakdown = ColorSchemeManager.shared.typeBreakdown(for: rootNode)
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
    let onTap: (TreeMapRectangle) -> Void
    let onLongPress: (TreeMapRectangle) -> Void
    let onDoubleTap: (TreeMapRectangle) -> Void

    @State private var hoveredRectangle: TreeMapRectangle?

    var body: some View {
        Canvas { context, size in
            // 绘制所有矩形 - 一次性完成，没有层级问题
            for rectangle in rectangles {
                drawRectangle(context: context, rectangle: rectangle)
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
                hoveredRectangle = findRectangleAt(location)
            case .ended:
                hoveredRectangle = nil
            }
        }
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
    private func drawRectangle(context: GraphicsContext, rectangle: TreeMapRectangle) {
        let rect = rectangle.rect
        let isHovered = hoveredRectangle?.id == rectangle.id

        // 绘制背景 - 高亮类型保持原色，其它降透
        let dimmed = highlightedFileType != nil && !isHighlighted(rectangle)
        let baseOpacity = isHovered ? 0.95 : 0.8
        let opacity = dimmed ? baseOpacity * 0.2 : baseOpacity
        context.fill(
            Path(rect),
            with: .color(rectangle.color.opacity(opacity))
        )

        // 绘制边框
        context.stroke(
            Path(rect),
            with: .color(rectangle.isImportant ? .primary.opacity(0.4) : .primary.opacity(0.2)),
            lineWidth: rectangle.isImportant ? 1.5 : 0.5
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

// MARK: - 详情面板视图
struct DetailsPanelView: View {
    @Binding var selectedNode: TreeNode?
    @Binding var showingDetails: Bool
    let fileSystemService: FileSystemService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("文件详情")
                    .font(.headline)

                Spacer()

                Button("x") {
                    showingDetails = false
                    selectedNode = nil
                }
                .buttonStyle(.plain)
            }

            if let selectedNode = selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedNode.item.name)
                        .font(.title3)
                        .fontWeight(.medium)

                    Text(
                        "大小: \(ByteCountFormatter.string(fromByteCount: selectedNode.totalSize, countStyle: .file))"
                    )
                    .font(.body)

                    Text("类型: \(selectedNode.item.isDirectory ? "文件夹" : "文件")")
                        .font(.body)

                    Text("路径:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(selectedNode.item.path.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if selectedNode.item.isDirectory && !selectedNode.children.isEmpty {
                        ChildrenListView(
                            selectedNode: selectedNode,
                            onSelectChild: { child in
                                self.selectedNode = child
                            })
                    }

                    Spacer()

                    ActionsView(
                        selectedNode: selectedNode,
                        fileSystemService: fileSystemService,
                        onClose: {
                            showingDetails = false
                            self.selectedNode = nil
                        }
                    )
                }
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .onTapGesture {
            showingDetails = false
            selectedNode = nil
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
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button("在Finder中显示") {
                NSWorkspace.shared.selectFile(
                    selectedNode.item.path.path,
                    inFileViewerRootedAtPath: ""
                )
            }
            .buttonStyle(.borderedProminent)

            if selectedNode.item.isDirectory {
                Button("重新扫描此文件夹") {
                    fileSystemService.scanDirectory(at: selectedNode.item.path)
                    onClose()
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { onSelect(node) }) {
                        Text(node.item.name)
                            .font(.caption)
                            .foregroundColor(index == path.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
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
                value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                label: "总大小"
            )
            MetricBlock(
                icon: "doc.fill",
                value: "\(fileCount)",
                label: "文件"
            )
            MetricBlock(
                icon: "folder.fill",
                value: "\(folderCount)",
                label: "文件夹"
            )
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
}

struct MetricBlock: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.primary)
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
                        ForEach(entries.filter { $0.size > 0 }) { entry in
                            entry.color
                                .frame(width: geo.size.width * entry.ratio)
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)
            .help(tooltipText)
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
        .frame(width: 200)
        .background(.regularMaterial)
    }
}

struct LegendRow: View {
    let entry: ColorSchemeManager.TypeBreakdownEntry
    let isHighlighted: Bool

    var body: some View {
        let pct = entry.total > 0 ? Int(Double(entry.size) / Double(entry.total) * 100) : 0
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isHighlighted ? Color.primary : Color.clear, lineWidth: 2)
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
        .cornerRadius(4)
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
