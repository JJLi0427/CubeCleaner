# CubeCleaner v0.3.1 详情侧栏化 + 删除 + 钻取统计刷新设计

> **日期**：2026-06-25
> **范围**：详情面板从中间浮层挪进右侧侧栏（分页切换）；钻取后顶部统计随钻取根刷新；新增"移到废纸篓"删除按钮 + 二次确认 + 重扫
> **不含**：布局算法重写、多选删除、撤销删除

## 1. 背景与目标

v0.3 上线后三个问题：

1. **详情面板不合理**：选中块后详情（文件名/大小/路径/Finder 显示）以居中浮层出现，点空白即关，关掉就看不到信息。应挪进右侧侧栏常驻。
2. **钻取后统计不刷新**：双击进入"其他"或子目录后，屏幕已是细分块，但右侧/顶部统计仍显示整个扫描根的大小。根因：顶部 `StatsBarView` 读全局 `fileSystemService.totalSize/filesScanned/folderCount`，不随 `currentRoot` 变。
3. **缺删除能力**：Finder 显示按钮旁应有一个垃圾桶删除按钮，点击后二次确认再移到废纸篓。

目标：详情进侧栏分页、统计随钻取根刷新、新增移废纸篓删除（带二次确认）。

## 2. 整体布局变化

右侧侧栏从"纯图例"变为"分页侧栏"：

```
┌────────────────────────────────────────┬─────────────────┐
│                                        │ [图例] [详情]   │ ← Picker segmented
│        TreeMap Canvas                  ├─────────────────┤
│        ■■■■ ■■ ■■■ ■■■■               │ 图例页：        │
│        ■■■■ ■■ ■■■ ■■■■               │  ■ 图片 60GB 42%│
│                                        │  ■ 视频 40GB 28%│
│                                        │                 │
│                                        │ 详情页(选中块): │
│                                        │  📁 项目名       │
│                                        │  大小/类型/路径  │
│                                        │  子项目(48)      │
│                                        │  [Finder][🗑删除]│
└────────────────────────────────────────┴─────────────────┘
```

顶部统计条改为读**当前钻取根 currentRoot** 的子树聚合值（而非全局扫描值）。

中间浮层 `DetailsPanelView` 删除。

## 3. 组件设计

### 3.1 侧栏分页 SidebarTabView（新增，包住原 LegendSidebarView）

```
VStack(spacing: 0) {
    Picker("", selection: $sidebarTab) {
        Text("图例").tag(SidebarTab.legend)
        Text("详情").tag(SidebarTab.details)
    }
    .pickerStyle(.segmented)
    .padding(8)

    switch sidebarTab {
    case .legend: LegendSidebarView(...)        // 现有，不变
    case .details: DetailsSidebarView(...)      // 改名自 DetailsPanelView
    }
}
.frame(width: 200)
.background(.regularMaterial)
```

- `@State sidebarTab: SidebarTab = .legend`（默认图例）。
- 单击 Canvas 矩形 → 设 `selectedNode` + `sidebarTab = .details`（自动跳详情页）。
- 枚举 `SidebarTab { case legend, details }`。

### 3.2 DetailsSidebarView（改名自 DetailsPanelView，去浮层）

相比原 `DetailsPanelView` 的改动：
- 去 `.shadow`/`.cornerRadius(12)`/`.frame(maxWidth: 500)`/`.background(Color(...))`/`.onTapGesture { 关闭 }`。
- 去 `showingDetails` binding（不再需要开关）。
- 内容包进 `ScrollView`（侧栏全高可滚）。
- 保留：文件名/大小/类型/路径/子项目列表/`ActionsView`。
- 顶部不再要"×"关闭按钮（详情常驻侧栏，点别的块换内容即可）。
- 未选中任何块（`selectedNode == nil`）时显示占位："点击矩形查看详情"。

### 3.3 顶部统计随钻取根刷新

新增纯递归统计函数（放 `ColorSchemeManager` 或 `FileSystemService` 静态工具，纯函数）：

```swift
func fileCountInSubtree(_ node: TreeNode) -> Int    // 叶子文件数
func folderCountInSubtree(_ node: TreeNode) -> Int  // 目录数（含自身若为目录）
```

`ContentView` 新增状态：
```swift
@State private var subtreeTotalSize: Int64 = 0
@State private var subtreeFileCount: Int = 0
@State private var subtreeFolderCount: Int = 0
```

`updateLayoutOptimized` 末尾（与 `typeBreakdown` 同处刷新）：
```swift
let subRoot = currentRoot ?? rootNode
subtreeTotalSize = subRoot.totalSize
subtreeFileCount = ColorSchemeManager.shared.fileCountInSubtree(subRoot)
subtreeFolderCount = ColorSchemeManager.shared.folderCountInSubtree(subRoot)
```

`StatsBarView` 调用点改读这三个子树状态（而非 `fileSystemService.totalSize/filesScanned/folderCount`）。根目录时 `currentRoot == nil`，`subRoot = rootNode`，显示整盘值，与现状一致。

### 3.4 删除按钮（移到废纸篓 + 二次确认）

`ActionsView` 内"在 Finder 中显示"旁加：
```swift
Button {
    showingDeleteConfirm = true
} label: {
    Label("移到废纸篓", systemImage: "trash")
}
.buttonStyle(.bordered)
.tint(.red)
```

二次确认用 `.confirmationDialog`（挂在 ContentView 或 ActionsView 层级，`showingDeleteConfirm` 状态）：
- 标题：`"移到废纸篓"`
- 消息：`"将把「\(name)」（\(formattedSize)）移到废纸篓，可在废纸篓中恢复。确定继续？"`
- 按钮：`移到废纸篓`（role: .destructive）/ `取消`

确认执行（`FileSystemService` 新增 `trashAndRescan(deleteURL:scanRootURL:)` 或 ContentView 直接调）：
```swift
do {
    var resultingURL: NSURL?
    try FileManager.default.trashItem(at: deleteURL, resultingItemURL: &resultingURL)
    // 重扫扫描根
    if let scanRoot = scanRootURL { fileSystemService.scanDirectory(at: scanRoot) }
} catch {
    fileSystemService.errorMessage = "删除失败: \(error.localizedDescription)"
}
```

- `@State scanRootURL: URL?`：在 `fileImporter` 选目录时记录（`selectedPath = url; scanRootURL = url`）。
- 删除后重扫 → TreeMap/统计/图例自动同步（重扫会清 `rectangles`、重设 `rootNode`、触发 `.onChange(of: rootNode)` → 重算布局 + 子树统计）。
- 删除当前正在浏览的钻取根或其祖先时，`currentRoot` 可能指向已删节点 —— 重扫后 `rootNode` 变更，`.onChange(of: rootNode)` 把 `currentRoot = newNode`，回到新扫描根，安全。

### 3.5 entitlements 改动（删文件前提）

`CubeCleaner/CubeCleaner.entitlements`：
```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```
改为：
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```
否则沙盒会拒绝 `trashItem`。

## 4. 文件改动清单

- `CubeCleaner/CubeCleaner.entitlements`：read-only → read-write。
- `CubeCleaner/Service/CubeCleanerBackend.swift`：
  - `ColorSchemeManager`（或合适位置）加 `fileCountInSubtree(_:)` / `folderCountInSubtree(_:)` 纯递归统计。
  - `FileSystemService` 加 `trashAndRescan(deleteURL:scanRootURL:)`（trashItem + scanDirectory + 错误处理），或由 ContentView 直接调（二选一，实现时定）。
- `CubeCleaner/ContentView.swift`：
  - 新增 `@State sidebarTab / scanRootURL / showingDeleteConfirm / subtreeTotalSize / subtreeFileCount / subtreeFolderCount`。
  - 删除 `@State showingDetails`（浮层开关）。
  - 侧栏 `if showLegend { LegendSidebarView }` → 包成 `SidebarTabView`（Picker + 分页）。
  - `DetailsPanelView` 改名 `DetailsSidebarView`，去浮层样式，加 ScrollView + 空态占位。
  - 删除中间 `if showingDetails { DetailsPanelView(...) }` 浮层块。
  - Canvas `onTap`：`selectedNode = rectangle.node; sidebarTab = .details`（去掉 `showingDetails = true`）。
  - `ActionsView` 加删除按钮 + `.confirmationDialog`。
  - `updateLayoutOptimized` 末尾刷新三个子树统计。
  - `StatsBarView` 调用点改读子树状态。
  - `fileImporter` success 分支记录 `scanRootURL = url`。

## 5. 不做的事（YAGNI）

- 多选删除（仅删当前选中节点）。
- 撤销删除（废纸篓即恢复途径）。
- 删除进度条（单节点 trashItem 很快）。
- 布局算法重写。
- 顶部统计条加动画（直接刷新即可）。

## 6. 验证

无头环境无法跑 GUI，以 `./build.sh build` 通过为门槛。运行时验证项（用户本地 `./build.sh run`）：

- 选中块 → 侧栏自动跳详情页，详情常驻可滚，点别的块换内容。
- 双击进入"其他"/子目录 → 顶部统计与图例比例条随钻取根刷新。
- 垃圾桶按钮 → 二次确认 → 移废纸篓 → 重扫后 TreeMap 更新。
- 删除正在浏览的钻取根 → currentRoot 安全回到新扫描根。
- read-write entitlement 不影响扫描只读路径。
