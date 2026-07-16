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

⚠️ v0.3.3 已修复：`FileSystemService` 仍标 `@MainActor`（保证 `@Published` 写入与 SwiftUI 观察在主线程），但阻塞 IO 与树构建移至 `Task.detached(priority:.utility)` 后台线程（`performScanBackground` 等 `nonisolated` 方法），主线程仅做节流进度回写（50项/100ms）与最终接收 `rootNode`。扫描期间 UI 响应（resize/取消按钮可点）。

## 5. Services (实际)

### 5.1 FileSystemService (@MainActor)

```swift
@MainActor
class FileSystemService: ObservableObject {
    @Published var isScanning, scanProgress, currentPath, filesScanned, totalSize, rootNode, errorMessage
    func scanDirectory(at url: URL)                         // 主线程调，内部 Task.detached 跑后台
    func cancelScan()                                        // 取消 Task
    private nonisolated func performScanBackground(at:) async  // 后台入口：scope/建根/递归/排序/最终回写
    private nonisolated func scanRecursively(...) async       // 后台递归，深度上限 10
    private nonisolated func scanRecursivelyFallback(...) async // FileManager 回退
    private nonisolated func flushProgress(_:) async -> ScanProgress?  // 50项/100ms 节流回写
}
```

### 5.2 BulkFileScanner (static, 同步)

用 `getattrlistbulk` 批量读取目录条目属性（name/fsid/objtype/crtime/modtime/fileid/datalength），64KB 缓冲区，512 条/批。解析 `attrlist`/`attribute_set_t`/`attrreference`/`timespec`/`fsid_t` 二进制结构。

**属性请求位掩码**（`commonattr`）含 `ATTR_CMN_RETURNED_ATTRS`（`getattrlistbulk` 的必需位，缺它返回 EINVAL），其余按 `ATTR_CMN_*` 位序返回。每条目布局：`[UInt32 length][attribute_set_t 20B][attrreference name 8B][fsid_t 8B][UInt32 objType][timespec crtime 16B][timespec modtime 16B][UInt64 fileID][Int64 dataLength]`。文件名取值：`name = buf + nameRefPos + nameOffset`（`attr_dataoffset` 相对 `attrreference` 字段自身起始）。

`objType` 识别 `VDIR`（目录）/`VLNK`（符号链接）/`VREG`（普通文件）；目录与符号链接的 `datalength` 无业务意义，size 记 0。

### 5.3 扫描边界与去重 (v0.3.3, FR-006；v0.3.4 性能优化)

`FileSystemService.scanRecursively` / `processBatch` 对每个目录子项依次过三道闸门（回退路径 `scanRecursivelyFallback` 同步）：

1. **符号链接**（`objType==VLNK` / `lstat` `S_ISLNK`）：不跟随，标记 `scanBoundary=.symlink`，作为叶子，size 不计入。
2. **跨挂载点**：子目录本身是另一卷的挂载点（如 `/System/Volumes/Data`），不递归，标 `.crossVolume`，避免把整个数据卷算进来导致大小虚高。等价于 `du -x` / `find -x`。**v0.3.4 优化**：扫描开始时用 `getmntinfo` 一次取全部挂载点 `f_mntonname` 成 `Set<String>`，跨卷判断走 O(1) 集合查找，替代每目录 `statfs`（实测 /System 省 ~233ms）。回退路径无预构建集合时仍用单次 `statfs`。
3. **硬链接/firmlink 去重**：同一对象已在别处计入时不重复递归/计大小，标 `.alreadyCounted`。**v0.3.4 优化**：目录与文件统一用 bulk 返回的 `fileID`（ATTR_CMN_FILEID，已是 inode）去重，免每目录 `lstat`（实测省 ~333ms）；`fileID==0`（非 APFS 不可靠）时跳过去重，不误杀。根节点与回退路径（FileManager 无 bulk fileID）仍用 `lstat(dev,ino)`。

`Set<VisitKey>` 是扫描 Task 内局部状态，随扫描结束释放，不跨扫描泄漏。`TreeNode.scanBoundary` 驱动 `BinaryTreeMapCalculator.createLeafRectangle`（边界叶子用半透明中性灰）与 `TreeMapCanvasView.drawRectangle`（角标 SF Symbol：externaldrive/link/arrow.triangle.branch），`DetailsSidebarView` 显示对应说明。

**验证基准**：扫 `/System` 旧逻辑（跨卷不拦）= 305.88 GB（带进整个 Data 卷 + 各 APFS 分区卷），新逻辑（跨卷拦）= 28.16 GB（仅只读系统卷本身），拦下 7 个挂载点子目录。去重命中数与 totalSize 在 lstat 去重 vs bulk fileID 去重两版完全一致（`deduped=21325`、`total=28.16GB`），行为等价。

**性能基准**（/System，~48 万项）：v0.3.3 ~3793ms → v0.3.4 ~2620ms（省 ~31%）。剩余耗时几乎全是 `getattrlistbulk` 的 16 万次系统调用本身 + TreeNode 构建，无进一步压缩空间。

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

- **批量扫描**：`getattrlistbulk` 减少系统调用，64KB 缓冲区，`loadUnaligned` 解析（对齐安全）。
- **分批处理**：`chunked(into: 100)` 控制内存峰值。
- **后台扫描（v0.3.3, P0-3）**：阻塞 IO 与树构建跑在 `Task.detached(priority:.utility)` 后台线程（`performScanBackground` 等 `nonisolated` 方法）；`@Published` 写入经 `MainActor.run` 节流回写（50项/100ms），最终 `rootNode` 一次性回主线程。扫描期间 UI 不阻塞。
- **Canvas 渲染**：一次性绘制，无视图层级开销。
- **resize 防抖**：拖动清空，停手 0.3s 重算。
- **后台布局**：`Task.detached` 算布局，主线程仅赋值。
- **聚合降量**：小文件归入"其他"，矩形数大幅减少。
- **扫描后排序**：整树构建完后后台 `sortChildren` 降序，提升 TreeMap 布局质量。

### 9.2 待优化

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
