# CubeCleaner - Programming Design Documentation

## 1. Architecture Overview

### 1.1 实际架构 (v0.2)

CubeCleaner 当前是**轻量 SwiftUI + 单文件后端**结构，未采用 MVVM。状态管理直接用 `@StateObject` / `@State`，数据流为命令式调用。

```
┌──────────────────────┐   @StateObject    ┌─────────────────────────┐
│   ContentView        │──────────────────▶│   FileSystemService      │
│   (SwiftUI 主视图)    │                   │   (@MainActor)           │
│                      │   @State          │   • scanDirectory(at:)   │
│   • rectangles       │──────────────────▶│   • cancelScan()         │
│   • currentRoot      │                   │   • rootNode (@Published)│
│   • selectedNode     │   @State          │                          │
│                      │──────────────────▶│   BinaryTreeMapCalculator│
│   TreeMapCanvasView  │                   │   (布局算法)             │
│   BreadcrumbView     │                   └─────────────────────────┘
│   DetailsPanelView   │                              │
└──────────────────────┘                              │ getattrlistbulk
                                                      ▼
                                            ┌─────────────────────┐
                                            │ BulkFileScanner     │
                                            │ (static, 同步)      │
                                            └─────────────────────┘
```

### 1.2 核心原则（现状）
- **单文件后端**：`CubeCleanerBackend.swift` 含扫描/模型/颜色/布局/服务，1261 行，计划拆分（见 NEXT_STEPS P1）。
- **Canvas 渲染**：所有矩形一次性绘制，规避 SwiftUI 视图层级性能问题，自做 hit-test。
- **批量扫描**：`getattrlistbulk` 一次取多个文件属性，`FileManager` 回退。
- **resize 防抖**：拖动窗口时清空矩形，停手 0.3s 后重算。

## 2. Project Structure (实际)

```
CubeCleaner/
├── CubeCleanerApp.swift            # App 入口 (17 行)
├── ContentView.swift               # 主视图 + Canvas + 浮层 (670 行)
├── CubeCleaner.entitlements        # 沙盒权限 (user-selected.read-only)
├── Assets.xcassets/                # App 图标 / 强调色
└── Service/
    └── CubeCleanerBackend.swift     # 扫描/模型/颜色/布局/服务 (1261 行)
```

### 2.1 CubeCleanerBackend.swift 内部分块

该单文件按 MARK 分 5 块（见文件头注释）：

| 块 | 内容 | 行数(约) |
|----|------|----------|
| 扫描模块 | `BulkFileAttributes`、`BulkFileScanner` (getattrlistbulk) | 37-259 |
| 数据模型 | `FileSystemItem`、`TreeNode`、`FileType` | 261-425 |
| 可视化 | `ColorSchemeManager`、`TreeMapRectangle`、`BinaryTreeMapCalculator` | 426-944 |
| 文件系统服务 | `FileSystemService` (@MainActor) | 946-1224 |
| 工具 | `FileSystemError`、`Array.chunked` | 1226-1261 |

## 3. Core Models (实际代码)

### 3.1 FileSystemItem
文件系统项目的值类型，`Identifiable/Codable/Hashable`。实际字段无 `accessDate/fileType/permissions/children`（文档旧版的伪代码多写了这些）。

```swift
struct FileSystemItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date
    var formattedSize: String { ... }
    var isHidden: Bool { name.hasPrefix(".") }
    var fileExtension: String { path.pathExtension.lowercased() }
}
```

### 3.2 TreeNode
`ObservableObject` 类，递归树。`totalSize` 递归累加子项。

```swift
class TreeNode: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    @Published var children: [TreeNode] = []
    @Published var isExpanded: Bool = false
    private(set) var isAggregated: Bool = false   // 聚合"其他"节点标记

    func markAsAggregated() { isAggregated = true }
    var totalSize: Int64 { ... }   // 目录递归累加，文件返回 item.size
}
```

### 3.3 TreeMapRectangle
Canvas 矩形数据。`isAggregated` 标识"其他"块（v0.2 新增）。

```swift
struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let level: Int
    let isAggregated: Bool
    var shouldShowLabel: Bool { rect.width > 50 && rect.height > 20 }
    // ...displayName/canShowSize/formattedSize/isImportant 等计算属性
}
```

## 4. 状态管理 (无独立 ViewModel)

v0.2 未拆分 ViewModel，状态直接在 `ContentView` 与 `FileSystemService` 上。

- `ContentView`：`@StateObject fileSystemService`、`@State layoutCalculator`、`@State rectangles`、`@State currentRoot`、`@State selectedNode` 等。
- `FileSystemService`：`@MainActor ObservableObject`，`@Published` 暴露 `isScanning/scanProgress/rootNode` 等。

⚠️ 已知问题：`FileSystemService` 标 `@MainActor`，但 `BulkFileScanner.scanDirectory` 是同步阻塞 IO，大目录会卡 UI（见 NEXT_STEPS P0-3）。

## 5. Services (实际)

### 5.1 FileSystemService (@MainActor)

```swift
@MainActor
class FileSystemService: ObservableObject {
    @Published var isScanning, scanProgress, currentPath, filesScanned, totalSize, rootNode, errorMessage
    func scanDirectory(at url: URL)        // 启动 Task 扫描
    func cancelScan()                       // 取消 Task
    private func scanRecursively(node:currentDepth:) async   // 递归，深度上限 10
    private func scanRecursivelyFallback(...) async          // FileManager 回退
}
```

### 5.2 BulkFileScanner (static, 同步)

用 `getattrlistbulk` 批量读取目录条目属性（name/objtype/crtime/modtime/datalength），64KB 缓冲区，512 条/批。解析 `attrlist`/`attrreference`/`timespec` 二进制结构。

## 6. Layout Algorithm (实际：二分法 + 聚合)

### 6.1 BinaryTreeMapCalculator

采用递归二分（非 Squarified）。主入口 `calculateLayout(for:in:)`：

```swift
class BinaryTreeMapCalculator: ObservableObject {
    private let minVisibleSize: CGFloat = 24   // 矩形最小可见尺寸
    private let maxDepth: Int = 8              // 最大递归深度
    private let minFileRatio: Double = 0.005   // 聚合阈值 0.5%

    func calculateLayout(for node: TreeNode, in rect: CGRect) -> [TreeMapRectangle] {
        if rect.width < minVisibleSize || rect.height < minVisibleSize { return [] }
        globalMaxSize = findMaxSize(from: node)
        return binaryTreeMap(node: node, rect: rect, depth: 0)
    }
}
```

### 6.2 聚合"其他"块 (getValidChildren)

v0.2 改造：低于阈值的子项**不再丢弃**，聚合成一个虚拟"其他"节点，保证面积守恒。

```swift
private func getValidChildren(_ children: [TreeNode]) -> [TreeNode] {
    // 1. 过滤 size=0
    // 2. <=5 个直接返回
    // 3. 阈值 = 总大小 × 0.005
    // 4. >= 阈值保留；< 阈值聚合为"其他 (N 项)"虚拟节点
    // 5. 边界：全 < 阈值则保留前 10 大，不聚合
}
```

"其他"节点用中性灰，作为叶子矩形绘制，不参与递归二分。

### 6.3 二分核心 (binaryPartition)

按大小降序，`findBestSplitIndex` 找接近对半的分割点，长边方向二分，递归两侧。

### 6.4 展平 (flattenChildren)

`depth >= maxDepth` 时不再二分，线性排列剩余子项（按大小比例切长边）。

## 7. Key Views (实际)

### 7.1 ContentView
`VStack`：工具栏 → (GeometryReader 内 ZStack：面包屑 + TreeMapCanvasView + DetailsPanelView 浮层) → 状态栏。布局计算在 `updateLayoutOptimized`，用 `Task.detached` 后台算，回主线程 `withAnimation` 赋值。

### 7.2 TreeMapCanvasView
`Canvas` 一次性绘制所有 `rectangles`，`drawRectangle` 画填充+边框+标签。手势：
- `SpatialTapGesture`：单击 → 选中/详情
- `SpatialTapGesture(count: 2)`：双击 → 进入子目录
- `LongPressGesture`：长按 → Finder 显示
- `onContinuousHover`：悬停 → 更新 `hoveredRectangle` 高亮
- `findRectangleAt(_:)`：从后往前遍历命中检测

### 7.3 BreadcrumbView
从 `currentRoot` 沿 `parent` 上溯构造路径，点击某段切换 `currentRoot` 并重算布局。

### 7.4 DetailsPanelView / ChildrenListView / ActionsView
详情浮层：文件名/大小/类型/路径/子项目列表(前 50)/操作按钮(在 Finder 显示、重扫)。

## 8. Testing Strategy (现状)

⚠️ v0.2 **无任何测试**。计划在 NEXT_STEPS P1 补：
- 布局面积守恒、聚合阈值逻辑（`BinaryTreeMapCalculator`）
- `getattrlistbulk` buffer 解析（`BulkFileScanner`）
- `findRectangleAt` hit-test
- 详情面板点击冲突回归

## 9. Performance (实际优化点)

### 9.1 已实现
- **批量扫描**：`getattrlistbulk` 减少系统调用，64KB 缓冲区。
- **分批处理**：`chunked(into: 100)` 控制内存峰值，`Task.yield()` 让出主线程。
- **Canvas 渲染**：一次性绘制，无视图层级开销。
- **resize 防抖**：拖动清空，停手 0.3s 重算。
- **后台布局**：`Task.detached` 算布局，主线程仅赋值。
- **聚合降量**：小文件归入"其他"，矩形数大幅减少。

### 9.2 待优化
- 扫描移出主线程（P0-3）
- 整棵树常驻内存 → 懒加载/分页（P1）
- viewport culling（超大视图）

## 10. Error Handling (实际)

```swift
enum FileSystemError: LocalizedError {
    case accessDenied
    case invalidPath
    case scanCancelled
    var errorDescription: String? { ... }   // 中文本地化
}
```

- `BulkFileScanner` 解析失败的单条目跳过（`print` + continue），不中断整批。
- `scanRecursively` 失败回退 `scanRecursivelyFallback`（FileManager）。
- ⚠️ 错误处理较粗糙，无统一日志系统（计划见 NEXT_STEPS P1）。

本文档照实描述 v0.2 代码现状。目标架构与待办见 [NEXT_STEPS.md](../NEXT_STEPS.md)。
