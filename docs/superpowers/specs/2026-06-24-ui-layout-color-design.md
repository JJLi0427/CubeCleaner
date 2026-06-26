# CubeCleaner v0.3 页面布局与配色优化设计

> **日期**：2026-06-24
> **范围**：UI 视觉层重排 + 高饱和配色 + 类型占比统计与图例侧栏
> **不含**：布局算法重写、双模式调色、侧栏拖拽

## 1. 背景与目标

v0.2 当前布局问题：

1. **统计不显眼**：总大小/文件数只以 `.caption2` 二级灰色出现在工具栏右下角和底部状态栏，扫完一眼看不到总量。
2. **导航引导弱**：返回上一级只能点面包屑某段，新用户看不出能返回；面包屑占页面比例极小。
3. **配色单调**：8 个类型色中 document=.blue / video=.red / application=.gray / other=.systemGray，灰棕占比高，视觉不丰富。

目标：把统计提到顶部醒目位置、导航加独立返回按钮、换高饱和调色板、新增类型占比与图例侧栏。

## 2. 整体布局

自上而下四层 + 右侧图例侧栏：

```
┌──────────────────────────────────────────────────────────┐
│ [选择文件夹][取消扫描]                          [边栏▦]  │ ① 工具栏（加图例切换按钮）
├──────────────────────────────────────────────────────────┤
│ 💾 总大小 142.3 GB   📄 文件 48,231   📁 文件夹 1,203    │ ② 统计条（大号）
│ [■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■] 类型比例条(内联)   │
├──────────────────────────────────────────────────────────┤
│ ←返回上一级   根 › 用户 › 项目 › CubeCleaner             │ ③ 导航条（按钮+面包屑）
├────────────────────────────────────────┬─────────────────┤
│                                        │ 类型分布        │
│        TreeMap Canvas                  │ ■ 图片 60GB 42% │
│        ■■■■ ■■ ■■■ ■■■■               │ ■ 视频 40GB 28% │
│        ■■■■ ■■ ■■■ ■■■■               │ ■ 文档 12GB  8% │ ④ 图例侧栏（可隐藏）
│        ■■■■ ■■ ■■■ ■■■■               │ ...             │
└────────────────────────────────────────┴─────────────────┘
```

`ContentView` 根 `VStack` 结构：

```
VStack(spacing: 0) {
    ToolbarView          // ①
    Divider()
    StatsBarView         // ②
    Divider()
    NavigationBarView    // ③ (含返回按钮 + BreadcrumbView)
    HStack(spacing: 0) { // ④ 主内容
        GeometryReader { TreeMapCanvasView }  // ⑤
        if showLegend { LegendSidebarView }
    }
}
```

底部状态栏删除重复统计，仅保留版本号 / 错误信息行。

## 3. 组件设计

### 3.1 工具栏（改）

保留现有"选择文件夹""取消扫描"。右侧新增"边栏"切换按钮：

- `Button { showLegend.toggle() } label: { Image(systemName: showLegend ? "sidebar.left" : "sidebar.right") }`
- `.buttonStyle(.bordered)`
- 扫描进行中仍可切换（不影响扫描）

### 3.2 统计条 StatsBarView（新增）

三组指标水平排列 + 第二行内联比例条：

```
HStack {
    MetricBlock(icon: "externaldrive.fill", value: 总大小, label: "总大小")
    MetricBlock(icon: "doc.fill",          value: 文件数, label: "文件")
    MetricBlock(icon: "folder.fill",       value: 文件夹数, label: "文件夹")
    Spacer()
}
TypeRatioBarView(breakdown: breakdown)  // 第二行，全宽
```

- `MetricBlock`：`Image(systemName:)` + 大号数字（`.title2`、`.monospacedDigit()`、`.primary`）+ 小号标签（`.caption`、`.secondary`），垂直排版。
- 数据源：`rootNode.totalSize`、`fileSystemService.filesScanned`、`fileSystemService.folderCount`。
- 无扫描数据时整条隐藏，留"就绪"占位文案。
- 扫描中态：三指标显示当前累计值；比例条用不确定进度（`ProgressView().progressViewStyle(.linear)`）。

### 3.3 导航条 NavigationBarView（新增，含返回按钮）

```
HStack {
    Button("返回上一级") { currentRoot = currentRoot?.parent; relayout }
        .labelStyle(.titleAndIcon)
        .systemImage("chevron.backward")
        .disabled(currentRoot == nil || currentRoot == rootNode)
    Divider().vertical()
    BreadcrumbView(currentRoot, onSelect:)   // 沿用现有
}
.background(.ultraThinMaterial)
.zIndex(1)  // 浮于 Canvas
```

- 返回按钮：`Label("返回上一级", systemImage: "chevron.backward")`，`.buttonStyle(.bordered)`。
- 根目录禁用：`currentRoot == nil` 或 `currentRoot === rootNode` 时 `.disabled(true)`。
- 点击：`currentRoot = currentRoot?.parent`（nil 时回到根），`Task { await updateLayoutOptimized(size:) }`。
- 面包屑保持现有逻辑（路径上溯、chevron 分隔、当前段 primary）。

### 3.4 图例侧栏 LegendSidebarView（新增）

```
VStack {
    Text("类型分布").font(.headline)
    ScrollView {
        LazyVStack {
            ForEach(sortedBreakdown) { entry in
                LegendRow(color:, name:, size:, percent:)
                    .onTapGesture { toggleHighlight(entry.type) }
            }
        }
    }
}
.frame(width: 200)
.background(.regularMaterial)
```

- 数据源：`TypeBreakdown` 聚合（见 4.3），按大小降序。
- `LegendRow`：8pt 圆角色块 + 类型名 + `ByteCountFormatter` 大小 + 百分比。
- **点击高亮**：点中类型 → `highlightedFileType = type`（再点同类型取消，nil）。`TreeMapCanvasView` 接收该状态：高亮类型的矩形保持原色，其它降 `opacity(0.2)`。
- 宽度固定 200pt，不拖拽。
- 隐藏（`showLegend == false`）时 Canvas 占满全宽。

### 3.5 类型比例条 TypeRatioBarView（新增）

```
GeometryReader { geo in
    ZStack(alignment: .leading) {
        Capsule().fill(.quaternary)  // 底
        HStack(spacing: 0) {
            ForEach(sortedBreakdown) { entry in
                entry.color
                    .frame(width: geo.size.width * entry.ratio)
            }
        }
        .clipShape(Capsule())
    }
}
.frame(height: 10)
.help("\(name) · \(size) · \(percent%)")  // 悬停 tooltip
```

- 每段宽度 ∝ 该类型大小，按 8 类型配色。
- 悬停 tooltip：`"图片 · 60GB · 42%"`（整条 tooltip，不分区段命中——首版简化）。
- 无数据时显示 `.quaternary` 空 capsule。

## 4. 数据层改动

### 4.1 高饱和调色板（ColorSchemeManager）

替换 `fileTypeColors` 与 `directoryColor`：

| 类型 | 新色（RGB, sRGB 0-1） | hex |
|------|------|------|
| document | `(0.039, 0.518, 1.0)` | #0A84FF |
| image | `(0.188, 0.820, 0.345)` | #30D158 |
| video | `(1.0, 0.271, 0.227)` | #FF453A |
| audio | `(0.749, 0.353, 0.949)` | #BF5AF2 |
| archive | `(1.0, 0.624, 0.039)` | #FF9F0A |
| application | `(0.392, 0.824, 1.0)` | #64D2FF |
| system | `(1.0, 0.839, 0.039)` | #FFD60A |
| other | `(1.0, 0.216, 0.373)` | #FF375F |
| 文件夹 | `(0.251, 0.784, 0.878)` | #40C8E0 |

- `adjustedColor` 的大小→透明度映射保留：`opacity = 0.3 + ratio * 0.7`。
- 不做亮/暗模式分别调色。

### 4.2 folderCount（FileSystemService）

- 新增 `@Published var folderCount: Int = 0`。
- `scanDirectory(at:)` 开始时 `folderCount = 0`。
- 扫描递归中每遇到 `item.isDirectory` 的节点 `folderCount += 1`（在添加 childNode 处）。
- 取消扫描不回滚（保留已扫部分计数）。

### 4.3 TypeBreakdown 聚合函数

新增纯函数，统计条比例条与图例侧栏共用：

```swift
struct TypeBreakdownEntry: Identifiable {
    let id = UUID()
    let type: FileType
    let size: Int64
    let color: Color
    let ratio: CGFloat      // size / total
}

func typeBreakdown(for node: TreeNode) -> [TypeBreakdownEntry] {
    // 遍历 node 子树所有叶子文件，按 FileType 累加 item.size
    // 文件夹不计入（避免与子文件重复）
    // total = 所有类型 size 之和
    // 返回 8 类型（含 size=0），降序
}
```

- 放在 `ColorSchemeManager` 或独立 extension；调用 `FileType.from(extension:)`。
- 聚合当前 `currentRoot` 子树（钻取后图例随根变化）。

## 5. TreeMapCanvasView 高亮

- `TreeMapCanvasView` 新增参数 `highlightedFileType: FileType?`。
- `drawRectangle`：若 `highlightedFileType != nil` 且当前矩形 `FileType != highlightedFileType`，绘制时 fill 用 `color.opacity(color.opacity * 0.2)`（或直接 `opacity(0.2)`）；高亮类型矩形保持 `color`。
- 文件夹矩形：`highlightedFileType != nil` 时统一降 `opacity(0.2)`（文件夹无单一类型）。
- `nil` 时全部原色。

## 6. 状态新增

`ContentView` 新增：

- `@State private var showLegend: Bool = true`
- `@State private var highlightedFileType: FileType? = nil`
- `@State private var typeBreakdown: [TypeBreakdownEntry] = []`（每次重算布局后刷新）

`updateLayoutOptimized` 末尾追加：

```swift
typeBreakdown = ColorSchemeManager.shared.typeBreakdown(for: rootNode)
```

## 7. 文件改动清单

- `CubeCleaner/Service/CubeCleanerBackend.swift`
  - `ColorSchemeManager`：替换 8 类型色 + 文件夹色为高饱和 RGB；新增 `TypeBreakdownEntry` 与 `typeBreakdown(for:)`。
  - `FileSystemService`：新增 `@Published folderCount`，扫描累计。
- `CubeCleaner/ContentView.swift`
  - 工具栏加"边栏"按钮。
  - 新增 `StatsBarView`、`MetricBlock`、`TypeRatioBarView`、`NavigationBarView`（返回按钮 + 现有 `BreadcrumbView`）、`LegendSidebarView`、`LegendRow`。
  - 根 `VStack` 重排为四层 + `HStack`(Canvas + 侧栏)。
  - 删除底部状态栏重复统计。
  - `TreeMapCanvasView` 加 `highlightedFileType` 参数 + 绘制降透。
  - `updateLayoutOptimized` 末尾刷新 `typeBreakdown`。

## 8. 不做的事（YAGNI）

- 侧栏宽度拖拽（固定 200pt）。
- 亮/暗模式分别调色。
- 比例条区段命中 tooltip（仅整条 tooltip）。
- 布局算法重写（上一轮已优化，本次只动视觉层）。
- 文件夹数深度上限之外的聚合修正。

## 9. 验证

无头环境无法跑 GUI，以 `./build.sh build` 通过为门槛。运行时验证项（用户本地 `./build.sh run`）：

- 顶部统计条三指标醒目、比例条多色。
- 返回按钮在子目录可点、根目录变灰。
- 图例侧栏可显隐、点击类型高亮 TreeMap。
- 高饱和配色不刺眼、各类别可辨。
