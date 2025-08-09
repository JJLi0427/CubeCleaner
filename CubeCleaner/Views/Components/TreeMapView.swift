//
//  TreeMapView.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import SwiftUI

/// 树状图主视图
/// 渲染文件系统的树状图可视化界面
struct TreeMapView: View {
    
    // MARK: - Properties
    
    @ObservedObject var viewModel: TreeMapViewModel
    @State private var viewportSize: CGSize = .zero
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color(.controlBackgroundColor)
                    .ignoresSafeArea()
                
                // 树状图内容
                if let rootNode = viewModel.currentRootNode {
                    TreeMapContentView(
                        rootNode: rootNode,
                        viewModel: viewModel
                    )
                    .clipped()
                } else {
                    // 空状态
                    emptyStateView
                }
            }
            .onAppear {
                updateViewportSize(geometry.size)
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                updateViewportSize(newSize)
            }
            .gesture(
                SimultaneousGesture(
                    // 缩放手势
                    MagnificationGesture()
                        .onChanged { scale in
                            let center = CGPoint(
                                x: geometry.size.width / 2,
                                y: geometry.size.height / 2
                            )
                            viewModel.handleZoom(scale: scale, center: center)
                        },
                    
                    // 平移手势
                    DragGesture()
                        .onChanged { value in
                            viewModel.handlePan(translation: value.translation)
                        }
                )
            )
            .onTapGesture { location in
                viewModel.handleTap(at: location)
            }
            .onHover { isHovering in
                if !isHovering {
                    viewModel.handleHover(at: nil)
                }
            }
        }
    }
    
    // MARK: - Private Views
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("选择一个文件夹开始扫描")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("使用左侧边栏选择要分析的文件夹")
                .font(.body)
                .foregroundColor(.tertiary)
        }
    }
    
    // MARK: - Private Methods
    
    private func updateViewportSize(_ size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        viewModel.viewportSize = size
    }
}

// MARK: - TreeMapContentView

/// 树状图内容视图
/// 负责渲染具体的树状图节点
struct TreeMapContentView: View {
    let rootNode: TreeNode
    @ObservedObject var viewModel: TreeMapViewModel
    
    var body: some View {
        Canvas { context, size in
            // 渲染所有可见的节点
            renderNodes(context: context, node: rootNode)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                viewModel.handleHover(at: location)
            case .ended:
                viewModel.handleHover(at: nil)
            }
        }
    }
    
    // MARK: - Rendering
    
    private func renderNodes(context: GraphicsContext, node: TreeNode) {
        // 如果节点太小，不渲染
        let displayRect = viewModel.getDisplayRect(for: node)
        guard displayRect.width > 1 && displayRect.height > 1 else { return }
        
        // 渲染当前节点
        renderNode(context: context, node: node, rect: displayRect)
        
        // 递归渲染子节点
        if !node.children.isEmpty && displayRect.width > 10 && displayRect.height > 10 {
            for child in node.children {
                renderNodes(context: context, node: child)
            }
        }
    }
    
    private func renderNode(context: GraphicsContext, node: TreeNode, rect: CGRect) {
        let path = Path(rect)
        let color = viewModel.getColor(for: node)
        
        // 绘制填充
        context.fill(path, with: .color(color))
        
        // 绘制边框
        let borderColor = getBorderColor(for: node)
        context.stroke(path, with: .color(borderColor), lineWidth: 1)
        
        // 绘制标签
        if viewModel.shouldShowLabel(for: node) {
            drawLabel(context: context, node: node, rect: rect)
        }
    }
    
    private func getBorderColor(for node: TreeNode) -> Color {
        if viewModel.selectedNode?.id == node.id {
            return .accentColor
        } else if viewModel.hoveredNode?.id == node.id {
            return .secondary
        } else {
            return Color(.separatorColor)
        }
    }
    
    private func drawLabel(context: GraphicsContext, node: TreeNode, rect: CGRect) {
        let item = node.fileSystemItem
        let name = item.name
        let size = ByteCountFormatter.string(fromByteCount: item.totalSize, countStyle: .file)
        
        // 计算文字大小
        let fontSize = min(12, rect.height * 0.2)
        guard fontSize >= 8 else { return }
        
        // 绘制文件名
        let namePosition = CGPoint(
            x: rect.midX,
            y: rect.midY - fontSize/2
        )
        
        context.draw(
            Text(name)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(.primary),
            at: namePosition,
            anchor: .center
        )
        
        // 如果空间足够，绘制大小信息
        if rect.height > fontSize * 3 {
            let sizePosition = CGPoint(
                x: rect.midX,
                y: rect.midY + fontSize/2
            )
            
            context.draw(
                Text(size)
                    .font(.system(size: fontSize * 0.8))
                    .foregroundColor(.secondary),
                at: sizePosition,
                anchor: .center
            )
        }
    }
}

// MARK: - Preview

#Preview {
    // 创建示例数据
    let sampleItem = FileSystemItem(
        name: "Documents",
        path: URL(fileURLWithPath: "/Users/sample/Documents"),
        size: 1024 * 1024 * 100, // 100MB
        isDirectory: true,
        fileType: .directory
    )
    
    let sampleNode = TreeNode(fileSystemItem: sampleItem)
    let viewModel = TreeMapViewModel()
    viewModel.setTreeData(sampleNode)
    
    return TreeMapView(viewModel: viewModel)
        .frame(width: 800, height: 600)
}
