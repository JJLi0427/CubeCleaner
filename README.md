# CubeCleaner

[![Release](https://github.com/JJLi0427/CubeCleaner/actions/workflows/release.yml/badge.svg)](https://github.com/JJLi0427/CubeCleaner/actions/workflows/release.yml)

A macOS disk usage visualization application built with Swift and SwiftUI, inspired by GrandPerspective. CubeCleaner provides an intuitive tree map visualization of your disk usage, helping you identify large files and folders to manage your disk space effectively.

**当前状态：v0.3.2-beta，图例/详情同列双区、同类型内大小调深度配色可用。**

## Features (v0.3.2)

- 🗂️ **Visual Disk Analysis**: TreeMap 可视化，矩形面积与文件大小成比例
- 🧩 **小文件聚合**: 低于阈值的文件自动归入"其他"块，面积守恒，无过细矩形
- 🎨 **按类型配色**: 文件按类型（文档/图片/视频/音频/压缩包/应用/系统）着色
- 🖱️ **基础交互**: 单击查看详情、双击进入子目录、长按在 Finder 中显示、悬停高亮
- 🧭 **面包屑导航**: 显示当前路径，点击任意层级快速返回
- ⚡ **批量扫描**: 使用 `getattrlistbulk` 批量读取文件属性，`FileManager` 回退
- 🖥️ **Canvas 渲染**: 一次性绘制所有矩形，窗口缩放防抖重算
- 📊 **顶部统计条**: 总大小/文件数/文件夹数大号显示 + 类型占比比例条
- 🗂️ **类型图例侧栏**: 右侧列各类型大小占比，点击高亮 TreeMap 中该类型矩形
- 🎨 **高饱和配色**: 8 文件类型 + 文件夹采用高饱和 RGB，颜色丰富易辨
- ↩️ **返回导航**: 独立"返回上一级"按钮，根目录自动禁用
- 🗑️ **移到废纸篓**: 详情页垃圾桶按钮 + 二次确认，删除后自动重扫
- 🔄 **钻取统计刷新**: 进入子目录/聚合块后顶部统计随钻取根刷新
- 🗂️ **图例/详情双区侧栏**: 图例上、详情下同列堆叠，同屏可见无需切换
- 🎨 **类型内深度配色**: 同类型下越大越深(调亮度)，以类型内最大块为基准

> 以下为规划中功能（见 Roadmap 与 NEXT_STEPS）：文件名/类型/大小/日期过滤、多视图、保存与导出（PNG/CSV/JSON）、缩放平移、Quick Look 预览、键盘快捷键。

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

### Distribution (CI builds)

合并到 `main` 或推送 `v*` tag 会自动构建 Release DMG 并发布到 [GitHub Releases](https://github.com/JJLi0427/CubeCleaner/releases)。DMG 为 **ad-hoc 签名**（`CODE_SIGN_IDENTITY="-"`，无 Developer ID、未公证）——在其他 Mac 上首次打开会被 Gatekeeper 拦截，请右键 → 打开，或拖到 /Applications 后运行 `xattr -dr com.apple.quarantine /Applications/CubeCleaner.app`。

## Development Roadmap

### Phase 1: Core Infrastructure ✅ (v0.2)
- [x] 基础项目结构与架构
- [x] 文件系统扫描引擎 (getattrlistbulk 批量扫描)
- [x] 树形数据结构 (TreeNode)
- [x] 基础 SwiftUI 视图

### Phase 2: Visualization ✅ (v0.2)
- [x] TreeMap 布局算法 (二分法 + 聚合"其他"块)
- [x] Canvas 矩形渲染
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