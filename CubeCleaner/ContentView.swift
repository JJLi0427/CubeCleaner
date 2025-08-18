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
    @State private var showingDetails = false
    @State private var showingFilePicker = false

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

                    if rectangles.isEmpty && !fileSystemService.isScanning {
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

                            // Button("选择文件夹") {
                            //     showingFilePicker = true
                            // }
                            // .buttonStyle(.borderedProminent)
                            // .controlSize(.large)
                        }
                        .frame(maxWidth: 400)
                    } else if !rectangles.isEmpty {
                        // TreeMap 可视化
                        ScrollView([.horizontal, .vertical]) {
                            ZStack {
                                ForEach(rectangles) { rectangle in
                                    TreeMapRectangleView(rectangle: rectangle)
                                        .onTapGesture {
                                            selectedNode = rectangle.node
                                            showingDetails = true
                                        }
                                }
                            }
                            .frame(
                                width: max(geometry.size.width, 1000),
                                height: max(geometry.size.height, 800)
                            )
                        }
                        .coordinateSpace(name: "scrollView")
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
                                Text("\(fileSystemService.filesScanned) 个文件已扫描")
                                    .font(.body)
                                    .foregroundColor(.secondary)

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
                    }
                }
                .onAppear {
                    updateLayout(size: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    updateLayout(size: newSize)
                }
                .onChange(of: fileSystemService.rootNode) { _, _ in
                    updateLayout(size: geometry.size)
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

    private func updateLayout(size: CGSize) {
        guard let rootNode = fileSystemService.rootNode, size.width > 0, size.height > 0 else {
            rectangles = []
            return
        }

        let rect = CGRect(origin: .zero, size: size)
        rectangles = layoutCalculator.calculateLayout(for: rootNode, in: rect)
    }
}

struct TreeMapRectangleView: View {
    let rectangle: TreeMapRectangle
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // 背景矩形
            Rectangle()
                .fill(rectangle.color.opacity(isHovered ? 0.95 : 0.8))
                .stroke(
                    rectangle.isImportant ? Color.primary.opacity(0.4) : Color.primary.opacity(0.2),
                    lineWidth: rectangle.isImportant ? 1.5 : 0.5
                )
                .shadow(
                    color: .black.opacity(isHovered ? 0.3 : 0.1),
                    radius: isHovered ? 3 : 1
                )

            // 内容标签
            if rectangle.shouldShowLabel {
                VStack(spacing: 2) {
                    // 文件/文件夹名称
                    if !rectangle.displayName.isEmpty {
                        Text(rectangle.displayName)
                            .font(.system(size: min(11, rectangle.rect.height / 4)))
                            .fontWeight(rectangle.isImportant ? .semibold : .medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                    }

                    // 大小信息
                    if rectangle.canShowSize {
                        Text(rectangle.formattedSize)
                            .font(.system(size: min(9, rectangle.rect.height / 6)))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // 详细信息（文件夹子项数量）
                    if rectangle.canShowDetails && rectangle.node.item.isDirectory {
                        Text(rectangle.childrenDescription)
                            .font(.system(size: min(8, rectangle.rect.height / 8)))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(2)
                .frame(maxWidth: rectangle.rect.width - 4, maxHeight: rectangle.rect.height - 4)
            }

            // 文件类型图标（仅对重要文件显示）
            if rectangle.isImportant && !rectangle.node.item.isDirectory
                && rectangle.rect.width > 30 && rectangle.rect.height > 30
            {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: iconForFileType(rectangle.node.item.fileExtension))
                            .font(.system(size: min(12, rectangle.rect.width / 8)))
                            .foregroundColor(.primary.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .frame(width: rectangle.rect.width, height: rectangle.rect.height)
        .position(x: rectangle.rect.midX, y: rectangle.rect.midY)
        .onTapGesture {
            // 点击打开文件或文件夹
            NSWorkspace.shared.selectFile(
                rectangle.node.item.path.path,
                inFileViewerRootedAtPath: ""
            )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(makeTooltipText())
    }

    /**
     * 根据文件扩展名返回合适的图标
     */
    private func iconForFileType(_ extension: String) -> String {
        let ext = `extension`.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp", "heic":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "m4v":
            return "play.rectangle"
        case "mp3", "wav", "aac", "flac", "ogg", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "txt", "md":
            return "doc.text"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        case "app":
            return "app"
        case "dmg":
            return "externaldrive"
        default:
            return "doc"
        }
    }

    /**
     * 生成工具提示文本
     */
    private func makeTooltipText() -> String {
        var tooltip = "\(rectangle.node.item.name)\n"
        tooltip += "大小: \(rectangle.formattedSize)\n"
        tooltip += "类型: \(rectangle.node.item.isDirectory ? "文件夹" : "文件")\n"

        if rectangle.node.item.isDirectory && !rectangle.node.children.isEmpty {
            tooltip += "包含: \(rectangle.node.children.count) 项\n"
        }

        tooltip += "路径: \(rectangle.node.item.path.path)"
        return tooltip
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
        .frame(width: 300)
        .background(Color(NSColor.controlBackgroundColor))
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

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
