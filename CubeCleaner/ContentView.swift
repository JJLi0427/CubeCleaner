//
//  ContentView.swift
//  CubeCleaner
//
//  Created by 李佳骏 on 2025/8/7.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var fileSystemService = FileSystemService()
    @State private var layoutCalculator = BinaryTreeMapCalculator()
    @State private var rectangles: [TreeMapRectangle] = []
    @State private var selectedPath: URL?
    @State private var hoveredNode: TreeNode?
    @State private var selectedNode: TreeNode?
    @State private var currentRoot: TreeNode?
    @State private var showingFilePicker = false

    // v0.3: 类型高亮 + 类型分布（图例已改横向条，不再有侧栏开关）
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

    /// TreeMap 顶部为浮动的 NavigationBarView（返回+面包屑）预留的高度，
    /// 避免最上面一排矩形的文件名被导航条挡住。导航条实际约 36pt，取 40 留余量。
    private let navBarReservedHeight: CGFloat = 40

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
            }
            .padding()
            .glassBackground()

            Divider()

            // 统计条 + 类型比例条 + 横向类型图例（均固定宽度，不遮挡地图）
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
                TypeLegendStripView(
                    entries: typeBreakdown,
                    highlightedFileType: highlightedFileType,
                    onToggleHighlight: { type in
                        highlightedFileType = (highlightedFileType == type) ? nil : type
                    }
                )
                Divider()
            }

            // 主内容区域：TreeMap（全宽，导航条浮于其顶部）
            GeometryReader { geometry in
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
                                // 单击选中：直接赋值，不加动画——选中描边瞬移到目标矩形，
                                // 即时反馈（避免 spring 0.4s 导致光标"滑过去"的迟滞感）。
                                selectedNode = rectangle.node
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
                        // 扫描状态：总数未知，用不确定进度条 + 实时计数(诚实无假跳)
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)

                            Text("正在扫描文件系统...")
                                .font(.title2)
                                .foregroundColor(.primary)

                            // 不确定流动条：持续动画，不谎报进度
                            ProgressView()
                                .progressViewStyle(.linear)
                                .frame(width: 300)

                            VStack(spacing: 4) {
                                Text("已扫描 \(fileSystemService.filesScanned) 项 · \(fileSystemService.folderCount) 个文件夹")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: Double(fileSystemService.filesScanned)))
                                    .animation(.easeOut(duration: 0.2), value: fileSystemService.filesScanned)

                                Text(
                                    "总大小: \(ByteCountFormatter.string(fromByteCount: fileSystemService.totalSize, countStyle: .file))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()

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

            // 底部详情条（选中/悬停项概要 + 操作）
            if fileSystemService.rootNode != nil {
                BottomDetailBarView(
                    node: hoveredNode ?? selectedNode,
                    fileSystemService: fileSystemService,
                    scanRootURL: scanRootURL,
                    onRequestDelete: { _ in
                        showingDeleteConfirm = true
                    }
                )
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
                Text("CubeCleaner v0.3.5")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .glassBackground()
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
        withAnimation(.easeOut(duration: 0.2)) {
            isLayouting = true
        }

        // 异步计算布局
        layoutTask = Task { @MainActor in
            // 在后台线程计算布局
            let calculator = layoutCalculator
            // 顶部为浮动的导航条预留高度，避免最上面一排矩形文件名被遮挡。
            let layoutRect = CGRect(
                x: 0,
                y: navBarReservedHeight,
                width: size.width,
                height: max(0, size.height - navBarReservedHeight)
            )
            let newRectangles = await Task.detached { [rootNode] in
                return calculator.calculateLayout(for: rootNode, in: layoutRect)
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

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
