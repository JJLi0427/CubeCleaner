//
//  ContentView.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import SwiftUI

struct ContentView: View {
    
    // MARK: - View Models
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var treeMapViewModel = TreeMapViewModel()
    
    // MARK: - State
    @State private var selectedSidebarItem: SidebarItem = .volumes
    
    var body: some View {
        NavigationSplitView {
            // 左侧边栏
            SidebarView(
                scanViewModel: scanViewModel,
                selectedItem: $selectedSidebarItem
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // 主内容区域
            MainContentView(
                scanViewModel: scanViewModel,
                treeMapViewModel: treeMapViewModel
            )
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            // 右侧详情面板
            DetailPanelView(
                scanViewModel: scanViewModel,
                treeMapViewModel: treeMapViewModel
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        }
        .onAppear {
            setupViewModelBindings()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupViewModelBindings() {
        // 监听扫描完成，更新树状图
        scanViewModel.$rootNode
            .compactMap { $0 }
            .sink { rootNode in
                treeMapViewModel.setTreeData(rootNode)
            }
            .store(in: &scanViewModel.cancellables)
    }
}

// MARK: - Supporting Views

/// 侧边栏视图
struct SidebarView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @Binding var selectedItem: SidebarItem
    
    var body: some View {
        List(selection: $selectedItem) {
            Section("扫描") {
                Label("卷", systemImage: "externaldrive")
                    .tag(SidebarItem.volumes)
                
                Label("最近", systemImage: "clock")
                    .tag(SidebarItem.recent)
            }
            
            Section("过滤器") {
                Label("文件类型", systemImage: "doc.text")
                    .tag(SidebarItem.fileTypes)
                
                Label("大小", systemImage: "ruler")
                    .tag(SidebarItem.sizes)
            }
        }
        .navigationTitle("CubeCleaner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("扫描", systemImage: "magnifyingglass") {
                    scanViewModel.startScan()
                }
                .disabled(scanViewModel.scanningState == .scanning)
            }
        }
    }
}

/// 主内容视图
struct MainContentView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var treeMapViewModel: TreeMapViewModel
    
    var body: some View {
        VStack {
            // 工具栏
            MainToolbarView(
                scanViewModel: scanViewModel,
                treeMapViewModel: treeMapViewModel
            )
            
            // 树状图视图
            TreeMapView(viewModel: treeMapViewModel)
                .background(Color(.controlBackgroundColor))
            
            // 状态栏
            StatusBarView(scanViewModel: scanViewModel)
        }
        .navigationTitle("磁盘分析")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 主工具栏
struct MainToolbarView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var treeMapViewModel: TreeMapViewModel
    
    var body: some View {
        HStack {
            // 导航控件
            HStack {
                Button("后退", systemImage: "chevron.left") {
                    treeMapViewModel.goBack()
                }
                .disabled(!treeMapViewModel.canGoBack)
                
                Button("前进", systemImage: "chevron.right") {
                    treeMapViewModel.goForward()
                }
                .disabled(!treeMapViewModel.canGoForward)
                
                Button("上级", systemImage: "chevron.up") {
                    treeMapViewModel.goUp()
                }
                .disabled(!treeMapViewModel.canGoUp)
            }
            
            Spacer()
            
            // 显示控件
            HStack {
                Picker("颜色方案", selection: $treeMapViewModel.colorScheme) {
                    ForEach(TreeMapColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                Toggle("标签", isOn: $treeMapViewModel.showLabels)
                    .toggleStyle(.button)
            }
            
            Spacer()
            
            // 缩放控件
            HStack {
                Button("缩小", systemImage: "minus.magnifyingglass") {
                    treeMapViewModel.zoomOut()
                }
                .disabled(!treeMapViewModel.canZoomOut)
                
                Button("适合", systemImage: "arrow.up.left.and.arrow.down.right") {
                    treeMapViewModel.zoomToFit()
                }
                
                Button("放大", systemImage: "plus.magnifyingglass") {
                    treeMapViewModel.zoomIn()
                }
                .disabled(!treeMapViewModel.canZoomIn)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
}

/// 详情面板
struct DetailPanelView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var treeMapViewModel: TreeMapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedNode = treeMapViewModel.selectedNode {
                // 选中项详情
                SelectedItemDetailView(node: selectedNode)
            } else {
                // 扫描统计
                ScanStatisticsView(statistics: scanViewModel.scanStatistics)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("详情")
    }
}

/// 状态栏
struct StatusBarView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    
    var body: some View {
        HStack {
            Text(scanViewModel.scanningState.description)
                .foregroundColor(.secondary)
            
            if scanViewModel.scanningState == .scanning {
                ProgressView(value: scanViewModel.scanProgress)
                    .frame(width: 100)
                
                Text(scanViewModel.currentScanPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.tertiary)
                    .font(.caption)
            }
            
            Spacer()
            
            if let rootNode = scanViewModel.rootNode {
                Text("\(rootNode.fileSystemItem.formattedSize())")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
    }
}

/// 选中项详情视图
struct SelectedItemDetailView: View {
    let node: TreeNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文件图标和名称
            HStack {
                Image(systemName: node.fileSystemItem.fileType.iconName)
                    .foregroundColor(Color(hex: node.fileSystemItem.fileType.colorHex))
                
                VStack(alignment: .leading) {
                    Text(node.fileSystemItem.name)
                        .font(.headline)
                    Text(node.fileSystemItem.fileType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // 详细信息
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "大小", value: node.fileSystemItem.formattedSize())
                InfoRow(label: "路径", value: node.fileSystemItem.path.path)
                
                if let modDate = node.fileSystemItem.modificationDate {
                    InfoRow(label: "修改时间", value: DateFormatter.localizedString(from: modDate, dateStyle: .medium, timeStyle: .short))
                }
                
                if node.fileSystemItem.isDirectory {
                    InfoRow(label: "文件数", value: "\(node.fileSystemItem.fileCount)")
                    InfoRow(label: "文件夹数", value: "\(node.fileSystemItem.directoryCount)")
                }
            }
        }
    }
}

/// 扫描统计视图
struct ScanStatisticsView: View {
    let statistics: ScanStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("扫描统计")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "文件总数", value: "\(statistics.fileCount)")
                InfoRow(label: "文件夹数", value: "\(statistics.directoryCount)")
                InfoRow(label: "总大小", value: statistics.formattedTotalSize)
                InfoRow(label: "扫描时间", value: statistics.formattedScanTime)
                InfoRow(label: "最大深度", value: "\(statistics.scanDepth)")
            }
        }
    }
}

/// 信息行组件
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
        }
        .font(.caption)
    }
}

// MARK: - Supporting Types

enum SidebarItem: String, CaseIterable {
    case volumes = "volumes"
    case recent = "recent"
    case fileTypes = "fileTypes"
    case sizes = "sizes"
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
