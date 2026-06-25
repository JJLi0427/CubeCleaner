# CubeCleaner v0.3.2 图例/详情分两区 + 同类型内大小调深度设计

> **日期**：2026-06-25
> **范围**：右侧侧栏由分页切换改为同列上下堆叠两区（图例上、详情下）；块颜色深度由"调透明度(全局基准)"改为"调亮度(类型内最大块基准)"
> **不含**：详情/图例高度拖拽、文件夹深度调节、亮暗模式分别调色、布局算法重写

## 1. 背景与目标

v0.3.1 上线后两个改进点：

1. **图例与详情分页切换不便**：`SidebarTabView` 用 Picker `[图例|详情]` 二选一，用户需手动切换才能在图例和详情间看。应改为同列上下堆叠，两块同屏可见。
2. **颜色深度不够直观**：当前 `adjustedColor` 用全局 `maxSize` 调透明度 `0.3 + ratio*0.7`，同类型下大块和小块只是透明度差异，不够"越深越大"。应改为调亮度——同类型内越大越深（越接近原饱和色），越小越浅。

目标：去分页、上下堆叠两区；颜色深度走亮度通道、按类型内最大块为基准。

## 2. 侧栏分两区

### 2.1 布局

右侧 200pt 列内 `VStack(spacing: 0)` 上下堆叠：

```
┌─────────────────┐
│ 类型分布        │ ← 图例区（上半）
│ ■ 图片 60GB 42% │
│ ■ 视频 40GB 28% │
│ ■ 文档 12GB  8% │
│ ...             │
├─────────────────┤
│ 选中详情        │ ← 详情区（下半）
│ 📁 项目名        │
│ 大小: 12.3 GB   │
│ 路径: /Users/.. │
│ 子项目(48)      │
│ [Finder][🗑删除]│
└─────────────────┘
```

### 2.2 组件

- 新增 `SidebarDualView`（替换 `SidebarTabView`）：
  ```
  VStack(spacing: 0) {
      LegendSidebarView(...)        // 上半，ScrollView 弹性占满
      Divider()
      DetailsSidebarView(...)       // 下半，ScrollView 内容驱动
  }
  .frame(width: 200)
  .background(.regularMaterial)
  ```
- 高度分配：图例区 `ScrollView` + 弹性高度（占剩余空间），详情区 `ScrollView` 按内容、设 `frame(minHeight: 240)` 避免过矮。两区都能独立滚动。
- 删除：`enum SidebarTab`、`struct SidebarTabView`、`@State sidebarTab`、Picker。
- `onTap`（Canvas 单击）去掉 `sidebarTab = .details`——详情区始终可见，点块直接刷新详情区内容。
- `showLegend` 侧栏显隐语义不变（显隐整列）。
- `LegendSidebarView` / `DetailsSidebarView` 内部各去掉自己的 `.frame(width: 200)`（宽度由 `SidebarDualView` 统一），保留各自 `ScrollView`/背景逻辑。

### 2.3 调用点

ContentView 侧栏块 `if showLegend { SidebarTabView(...) }` 改为 `if showLegend { SidebarDualView(...) }`。`SidebarDualView` 参数：`selectedNode: Binding<TreeNode?>`、`typeBreakdown`、`highlightedFileType`、`onToggleHighlight`、`fileSystemService`、`scanRootURL`、`onRequestDelete`（无 `sidebarTab`）。

## 3. 同类型内大小调深度（调亮度）

### 3.1 现状

`ColorSchemeManager.adjustedColor(for node: TreeNode, maxSize: Int64) -> Color`：用全局 `maxSize` 算 `ratio = node.totalSize / maxSize`，`opacity = 0.3 + ratio*0.7`，返回 `baseColor.opacity(opacity)`。即同类型大块更不透明、小块更透明。

### 3.2 新方案

改为调亮度，按**类型内最大块**为基准：

- `ratio = node.totalSize / maxSizeInType`（`maxSizeInType` = 当前布局子树内、与该节点同 FileType 的叶子文件里最大的 `totalSize`）。
- `ratio = 1`（类型内最大）→ 原饱和色（最深）。
- `ratio → 0`（类型内最小）→ 向浅色提亮。
- 提亮方式：RGB 各通道 `c' = c + (1 - c) * (1 - ratio) * k`，`k=0.6`（ratio=0 时各通道向白靠近 60%）。返回 `Color(red:c'_r, green:c'_g, blue:c'_b)`（不调透明度）。
- 文件夹：无单一类型，保持 `directoryColor.opacity(0.7)` 固定（不参与深度调节，YAGNI）。
- 聚合"其他"块：保持灰色 `Color(.systemGray).opacity(0.5)` 不变。

### 3.3 数据流

`BinaryTreeMapCalculator`：
- `calculateLayout(for:in:)` 入口先遍历叶子文件，按 `FileType` 分组取每类型最大 `totalSize`，存 `private var maxSizeByType: [FileType: Int64] = [:]`（实例状态，与现有 `globalMaxSize` 同级）。
- `createLeafRectangle(node:rect:depth:)`：非文件夹、非聚合时，取 `node` 的 FileType，`maxSizeInType = maxSizeByType[ft] ?? node.totalSize`，调 `colorSchemeManager.depthColor(for: node, maxSizeInType: maxSizeInType)`。
- 文件夹走 `directoryColor.opacity(0.7)`；聚合走灰色（现状不变）。

### 3.4 ColorSchemeManager 改动

- 新增 `func depthColor(for node: TreeNode, maxSizeInType: Int64) -> Color`：
  ```
  let baseColor = color(for: node)   // 取类型原色（文件夹分支已在调用方处理）
  guard maxSizeInType > 0 else { return baseColor }
  let ratio = Double(node.totalSize) / Double(maxSizeInType)
  // 取 baseColor RGB，按 ratio 提亮
  ... c' = c + (1-c)*(1-ratio)*0.6 ...
  return Color(red:c'_r, green:c'_g, blue:c'_b)
  ```
  取 RGB 用 `UIColor(baseColor).getRed(...)` 或直接基于 `fileTypeColors` 的已知 RGB 字面量计算（更稳，避免 UIColor 转换开销）——实现时优先用 `fileTypeColors` 字面量直接算（因为颜色是固定 RGB）。
- `adjustedColor(for:maxSize:)` 保留但不再被 `createLeafRectangle` 调用（避免破坏其它潜在调用点；若确认无其它调用，可删除——实现时 grep 确认）。

### 3.5 drawRectangle 透明度调整

现状 `drawRectangle`：`baseOpacity = isHovered ? 0.95 : 0.8`，`dimmed` 时 `* 0.2`。颜色深度现在走亮度通道而非透明度，故 `baseOpacity` 应为接近 1 的常量（如 0.85），让深度由颜色本身承载，hover 略提（0.95）。`dimmed` 高亮降透仍 `0.85 * 0.2`。

## 4. 文件改动清单

- `CubeCleaner/Service/CubeCleanerBackend.swift`：
  - `ColorSchemeManager`：新增 `depthColor(for:maxSizeInType:)`（按类型内最大块调亮度）；`adjustedColor` 视调用情况保留或删。
  - `BinaryTreeMapCalculator`：`calculateLayout` 入口算 `maxSizeByType`；`createLeafRectangle` 用 `depthColor`。
- `CubeCleaner/ContentView.swift`：
  - 删 `SidebarTab`/`SidebarTabView`/`sidebarTab`；新增 `SidebarDualView`（上下堆叠）。
  - `onTap` 去 `sidebarTab = .details`。
  - 侧栏调用点 `SidebarTabView` → `SidebarDualView`。
  - `LegendSidebarView`/`DetailsSidebarView` 去各自 `.frame(width: 200)`。
  - `drawRectangle` 的 `baseOpacity` 改常量（0.85，hover 0.95），深度走颜色。

## 5. 不做的事（YAGNI）

- 详情/图例区高度拖拽（固定分配）。
- 文件夹深度调节（固定色）。
- 亮/暗模式分别调色。
- 不改布局算法（仅新增 maxSizeByType 预计算）。
- 不调提亮系数 k 为用户可配（固定 0.6）。

## 6. 验证

无头环境无法跑 GUI，以 `./build.sh build` 通过为门槛。运行时验证项（用户本地 `./build.sh run`）：

- 图例区与详情区同屏上下可见，无需切换。
- 单击矩形 → 详情区刷新该块内容，图例区不变。
- 同类型下：大块颜色更深（接近原色），小块更浅；不同类型基准独立。
- 图例高亮点击 → TreeMap 非高亮类型降透，仍正常。
- 删除流程（侧栏详情区垃圾桶 + 二次确认）不受影响。
- 两区都能独立滚动，不互相挤压溢出。
