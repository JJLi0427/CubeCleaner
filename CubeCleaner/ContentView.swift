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

                // 状态信息
                VStack(alignment: .trailing, spacing: 2) {
                    if let selectedPath = selectedPath {
                        Text("已选择: \(selectedPath.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if fileSystemService.rootNode != nil {
                        Text(
                            "文件总数: \(fileSystemService.filesScanned) | 总大小: \(ByteCountFormatter.string(fromByteCount: fileSystemService.totalSize, countStyle: .file))"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 主内容区域
            GeometryReader { geometry in
                ZStack {
                    Color(.controlBackgroundColor)

                    // 面包屑导航 - 浮于 TreeMap 顶部，不挤压可视空间
                    VStack {
                        BreadcrumbView(
                            currentRoot: currentRoot,
                            onSelect: { node in
                                currentRoot = node
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        Spacer()
                    }

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
                                if rectangle.node.item.isDirectory && !rectangle.node.isAggregated {
                                    currentRoot = rectangle.node
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
                }
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

                // 详情面板
                if showingDetails {
                    DetailsPanelView(
                        selectedNode: $selectedNode,
                        showingDetails: $showingDetails,
                        fileSystemService: fileSystemService
                    )
                }
            }

            // 状态栏
            HStack {
                if let rootNode = fileSystemService.rootNode {
                    Text(
                        "总大小: \(ByteCountFormatter.string(fromByteCount: rootNode.totalSize, countStyle: .file))"
                    )
                    Spacer()
                    Text("文件数: \(fileSystemService.filesScanned)")
                } else if let errorMessage = fileSystemService.errorMessage {
                    Text("错误: \(errorMessage)")
                        .foregroundColor(.red)
                    Spacer()
                } else {
                    Text("就绪")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("CubeCleaner v0.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
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
            // 统一的点击手势处理 - 手动计算点击位置
            SpatialTapGesture()
                .onEnded { value in
                    if let hitRectangle = findRectangleAt(value.location) {
                        onTap(hitRectangle)
                    }
                }
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
        .onTapGesture(count: 2) { _ in
            // 双击由 DragGesture 的 location 无法直接拿到，改用 spatialTapGesture
        }
        .gesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    if let hitRectangle = findRectangleAt(value.location) {
                        onDoubleTap(hitRectangle)
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

    /**
     * 绘制单个矩形 - 直接Canvas绘制，无视图层级
     */
    private func drawRectangle(context: GraphicsContext, rectangle: TreeMapRectangle) {
        let rect = rectangle.rect
        let isHovered = hoveredRectangle?.id == rectangle.id

        // 绘制背景
        context.fill(
            Path(rect),
            with: .color(rectangle.color.opacity(isHovered ? 0.95 : 0.8))
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

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
