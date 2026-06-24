# CubeCleaner

A macOS disk usage visualization application built with Swift and SwiftUI, inspired by GrandPerspective. CubeCleaner provides an intuitive tree map visualization of your disk usage, helping you identify large files and folders to manage your disk space effectively.

**当前状态：v0.2-beta，基础扫描与 TreeMap 可视化可用。**

## Features

- 🗂️ **Visual Disk Analysis**: Tree map visualization showing files as rectangles proportional to their size
- 🎨 **Flexible Color Coding**: Color files by type, extension, size, date, or folder hierarchy
- 🔍 **Advanced Filtering**: Filter by file size, type, date, and custom criteria
- 📊 **Multiple Views**: Support for multiple simultaneous views and comparisons
- 💾 **Save & Export**: Save scan results and export as images or data files
- ⚡ **High Performance**: Optimized scanning and rendering for large file systems
- 🖱️ **Interactive Navigation**: Mouse and keyboard navigation with zoom and pan
- 🔗 **System Integration**: Quick Look preview, Finder integration, and file operations

## Documentation

This project includes comprehensive documentation to guide development:

- **[Requirements Documentation](docs/Requirements.md)** - Detailed functional and non-functional requirements
- **[Interface Design Documentation](docs/Interface-Design.md)** - UI/UX design specifications and interaction patterns  
- **[Programming Design Documentation](docs/Programming-Design.md)** - Architecture, models, and implementation details

## Project Structure

```
CubeCleaner/
├── CubeCleaner/                       # Main application
│   ├── CubeCleanerApp.swift           # App entry point
│   ├── ContentView.swift              # Main view + Canvas rendering + panels
│   ├── CubeCleaner.entitlements       # Sandbox permissions (read-only)
│   ├── Assets.xcassets/               # App icon & accent color
│   └── Service/
│       └── CubeCleanerBackend.swift   # 扫描/模型/颜色/布局/服务 (单文件)
├── CubeCleaner.xcodeproj/             # Xcode project
├── docs/                              # 文档 (Requirements/Interface/Programming)
├── build.sh                           # 构建脚本
└── README.md
```

## Getting Started

### Prerequisites

- macOS 15.5 or later
- Xcode 16.0 or later
- Swift 5.0 or later

### Building the Project

1. Clone the repository:
   ```bash
   git clone https://github.com/JJLi0427/CubeCleaner.git
   cd CubeCleaner
   ```

2. Open the project in Xcode:
   ```bash
   open CubeCleaner/CubeCleaner.xcodeproj
   ```

3. Build and run the project (⌘+R)

## Development Roadmap

### Phase 1: Core Infrastructure ✅ (v0.2)
- [x] 基础项目结构与架构
- [x] 文件系统扫描引擎 (getattrlistbulk 批量扫描)
- [x] 树形数据结构 (TreeNode)
- [x] 基础 SwiftUI 视图

### Phase 2: Visualization ✅ (v0.2)
- [x] TreeMap 布局算法 (二分法 + 聚合"其他"块)
- [x] Canvas 矩阵渲染
- [x] 颜色方案 (按文件类型)
- [x] 交互式导航 (双击进入子目录)

### Phase 3: User Interface 🚧 (部分完成)
- [x] 主窗口布局 (工具栏 + Canvas + 状态栏)
- [x] 详情面板
- [x] 面包屑导航
- [ ] 工具栏与菜单系统完善
- [ ] 偏好设置窗口

### Phase 4: Advanced Features ❌ (计划中)
- [ ] 过滤系统
- [ ] 搜索功能
- [ ] 导出功能
- [ ] 多视图支持

### Phase 5: Polish & Performance ❌ (计划中)
- [ ] 性能优化 (扫描移出主线程、内存优化)
- [ ] 错误处理标准化
- [ ] 无障碍功能
- [ ] App Store 准备

## Contributing

We welcome contributions! Please read our contributing guidelines and feel free to submit issues and pull requests.

## License

本项目采用 MIT License。⚠️ 注意：仓库当前尚未包含 LICENSE 文件，待后续补齐（见 NEXT_STEPS P2）。

## Inspiration

This project is inspired by [GrandPerspective](https://apps.apple.com/app/grandperspective/id1111570163), an excellent disk usage visualization tool for macOS. CubeCleaner aims to provide a modern, SwiftUI-based alternative with enhanced features and performance.