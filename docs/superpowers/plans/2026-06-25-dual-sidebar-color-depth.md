# CubeCleaner v0.3.2 图例/详情分两区 + 同类型内大小调深度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 右侧侧栏由分页切换改为同列上下堆叠两区（图例上、详情下），块颜色深度由"调透明度(全局基准)"改为"调亮度(类型内最大块基准)"。

**Architecture:** 纯 UI/配色层改造，不重写布局算法。数据层新增 `maxSizeByType` 预计算与 `depthColor` 调亮度方法；视图层把 `SidebarTabView` 分页替换为 `SidebarDualView` 上下堆叠，`drawRectangle` 透明度改常量让深度走颜色通道。

**Tech Stack:** Swift 5.0, SwiftUI, macOS 15.5 deployment target, Canvas rendering.

**Repo note:** 仓库无 XCTest target。本计划以 `./build.sh build` 通过为每任务验收门槛（替代单元测试）。所有 `git` 命令须 `git -C /Users/gwm/code/CubeCleaner`（工作目录是 `/Users/gwm`，不在仓库内）。

## Global Constraints

- 部署目标 macOS 15.5、Swift 5.0（与现有 Xcode 工程一致）。
- 不重写 `BinaryTreeMapCalculator` 布局算法（仅新增 `maxSizeByType` 预计算）。
- 颜色深度走亮度通道（非透明度），基准为该节点所属 FileType 在当前布局子树内的最大 `totalSize`。
- 提亮公式：RGB 各通道 `c' = c + (1 - c) * (1 - ratio) * 0.6`（ratio=1→原色，ratio=0→向白靠近 60%）。`k=0.6` 固定。
- 文件夹保持 `directoryColor.opacity(0.7)` 固定，不参与深度调节。
- 聚合"其他"块保持灰色不变。
- 侧栏固定 200pt 宽，上下堆叠两区，不分页。
- 提交信息中文，结尾含 `Co-Authored-By: Claude <noreply@anthropic.com>`。
- 所有改动在 `ljj/rebuild` 分支上提交。

---

## File Structure

- `CubeCleaner/Service/CubeCleanerBackend.swift` — `ColorSchemeManager` 加 `depthColor`；`BinaryTreeMapCalculator` 加 `maxSizeByType` 预计算 + `createLeafRectangle` 改用 `depthColor`。
- `CubeCleaner/ContentView.swift` — 删 `SidebarTab`/`SidebarTabView`/`sidebarTab`；新增 `SidebarDualView`；`onTap` 去跳详情页；侧栏调用点替换；`LegendSidebarView`/`DetailsSidebarView` 去各自 `.frame(width:200)`；`drawRectangle` 透明度改常量。

任务依赖：Task 1（depthColor 方法）→ Task 2（maxSizeByType 预计算 + createLeafRectangle 改用 depthColor）→ Task 3（drawRectangle 透明度改常量）→ Task 4（SidebarDualView + 删分页）→ Task 5（ContentView 组装 + onTap/侧栏调用点 + 子视图去 width）→ Task 6（最终构建 + 文档订正）。

---

### Task 1: ColorSchemeManager 加 depthColor 调亮度方法

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`ColorSchemeManager` 类内，`adjustedColor(for:maxSize:)` 方法之后，约 488 行）

**Interfaces:**
- Consumes: `TreeNode`、`FileType.from(extension:)`、`fileTypeColors`/`directoryColor`（现有）、`color(for:)`（现有）。
- Produces: `func depthColor(for node: TreeNode, maxSizeInType: Int64) -> Color`，供 Task 2 `createLeafRectangle` 调用。

- [ ] **Step 1: 在 adjustedColor 方法之后插入 depthColor**

在 `ColorSchemeManager` 类内 `adjustedColor(for:maxSize:)` 方法闭合 `}` 之后（约 488 行）、类闭合 `}` 之前插入：

```swift
    /// 按类型内最大块为基准调亮度：ratio=1(类型内最大)→原色最深，ratio→0→向浅提亮。
    /// 提亮公式：c' = c + (1-c)*(1-ratio)*0.6。文件夹/聚合由调用方处理，本方法仅处理普通文件。
    func depthColor(for node: TreeNode, maxSizeInType: Int64) -> Color {
        let baseColor = color(for: node)   // 取类型原色
        guard maxSizeInType > 0 else { return baseColor }
        let ratio = Double(node.totalSize) / Double(maxSizeInType)
        let clampedRatio = min(max(ratio, 0.0), 1.0)

        // 取基础色 RGB（UIColor 转换取分量）
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(baseColor).getRed(&r, green: &g, blue: &b, alpha: &a)

        let k: Double = 0.6
        let lighten = (1.0 - clampedRatio) * k
        let nr = r + (1.0 - r) * lighten
        let ng = g + (1.0 - g) * lighten
        let nb = b + (1.0 - b) * lighten
        return Color(red: nr, green: ng, blue: nb)
    }
```

> 注：用 `UIColor(baseColor).getRed(...)` 取分量是 macOS 上 SwiftUI Color 取 RGB 的标准做法（需 `import` 已有的 SwiftUI/AppKit，文件顶部已 `import SwiftUI`，`UIColor` 在 macOS 通过 Catalyst 可用——但本工程是原生 macOS，应用 `NSColor`）。**改用 NSColor**：把 `UIColor(baseColor).getRed(&r, green:&g, blue:&b, alpha:&a)` 改为 `NSColor(baseColor).usingColorSpace(.sRGB)?.getRed(&r, green:&g, blue:&b, alpha:&a)`，并 `import AppKit`（文件应已间接可用；若未 import，在文件顶部加 `import AppKit`）。最终实现以 NSColor 为准：

```swift
    func depthColor(for node: TreeNode, maxSizeInType: Int64) -> Color {
        let baseColor = color(for: node)
        guard maxSizeInType > 0 else { return baseColor }
        let ratio = Double(node.totalSize) / Double(maxSizeInType)
        let clampedRatio = min(max(ratio, 0.0), 1.0)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(baseColor).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

        let k: Double = 0.6
        let lighten = (1.0 - clampedRatio) * k
        let nr = r + (1.0 - r) * lighten
        let ng = g + (1.0 - g) * lighten
        let nb = b + (1.0 - b) * lighten
        return Color(red: nr, green: ng, blue: nb)
    }
```

实现者：先 `grep -n "^import" CubeCleaner/Service/CubeCleanerBackend.swift` 确认是否已 `import AppKit`；若无则在文件顶部 `import SwiftUI` 下加 `import AppKit`。用上面 NSColor 版本。

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ColorSchemeManager 加 depthColor 调亮度方法

按类型内最大块为基准调亮度，ratio=1 原色最深、ratio→0 向浅提亮，
供 createLeafRectangle 替代调透明度方案。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: BinaryTreeMapCalculator 加 maxSizeByType 预计算 + createLeafRectangle 改用 depthColor

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`BinaryTreeMapCalculator` 类：约 668 行 `globalMaxSize` 区、约 676 行 `calculateLayout`、约 984 行 `findMaxSize`、约 999 行 `createLeafRectangle`）

**Interfaces:**
- Consumes: Task 1 的 `depthColor(for:maxSizeInType:)`、`FileType.from(extension:)`、`TreeNode`。
- Produces: `createLeafRectangle` 用 `depthColor` 绘制普通文件块（深度走亮度），文件夹/聚合不变。

- [ ] **Step 1: 加 maxSizeByType 实例状态**

在 `BinaryTreeMapCalculator` 的 `private var globalMaxSize: Int64 = 0`（约 668 行）下一行加：

```swift
    private var maxSizeByType: [FileType: Int64] = [:]
```

- [ ] **Step 2: calculateLayout 入口算 maxSizeByType**

在 `calculateLayout(for:in:)` 内 `globalMaxSize = findMaxSize(from: node)`（约 683 行）下一行加：

```swift
        maxSizeByType = findMaxSizeByType(from: node)
```

- [ ] **Step 3: 新增 findMaxSizeByType 方法**

在 `findMaxSize(from:)` 方法（约 984 行）之后插入：

```swift
    /**
     * 查找每个 FileType 在子树内的最大叶子文件大小 - 用于颜色深度基准
     */
    private func findMaxSizeByType(from node: TreeNode) -> [FileType: Int64] {
        var result: [FileType: Int64] = [:]

        func traverse(_ current: TreeNode) {
            if current.item.isDirectory {
                current.children.forEach { traverse($0) }
            } else {
                let ft = FileType.from(extension: current.item.fileExtension)
                let cur = result[ft] ?? 0
                if current.totalSize > cur {
                    result[ft] = current.totalSize
                }
            }
        }
        traverse(node)
        return result
    }
```

- [ ] **Step 4: createLeafRectangle 改用 depthColor**

把 `createLeafRectangle`（约 999-1013 行）：

```swift
    private func createLeafRectangle(node: TreeNode, rect: CGRect, depth: Int, isAggregated: Bool = false) -> TreeMapRectangle {
        let color: Color
        if node.isAggregated {
            color = Color(.systemGray).opacity(0.5)
        } else {
            color = colorSchemeManager.adjustedColor(for: node, maxSize: globalMaxSize)
        }
        return TreeMapRectangle(
            node: node,
            rect: rect,
            color: color,
            level: depth,
            isAggregated: node.isAggregated
        )
    }
```

改为：

```swift
    private func createLeafRectangle(node: TreeNode, rect: CGRect, depth: Int, isAggregated: Bool = false) -> TreeMapRectangle {
        let color: Color
        if node.isAggregated {
            color = Color(.systemGray).opacity(0.5)
        } else if node.item.isDirectory {
            color = colorSchemeManager.colorForDirectory().opacity(0.7)
        } else {
            let ft = FileType.from(extension: node.item.fileExtension)
            let maxSizeInType = maxSizeByType[ft] ?? node.totalSize
            color = colorSchemeManager.depthColor(for: node, maxSizeInType: maxSizeInType)
        }
        return TreeMapRectangle(
            node: node,
            rect: rect,
            color: color,
            level: depth,
            isAggregated: node.isAggregated
        )
    }
```

> 注：文件夹分支显式走 `colorForDirectory().opacity(0.7)`（与 `color(for:)` 内文件夹分支一致），普通文件走 `depthColor`。`adjustedColor` 不再被调用——保留定义（grep 确认无其它调用点后可留可删，本任务保留以降风险）。

- [ ] **Step 5: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 6: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 布局预计算 maxSizeByType + createLeafRectangle 用 depthColor

calculateLayout 入口算每类型最大叶子文件大小，createLeafRectangle
普通文件按类型内最大块调亮度，文件夹固定色，聚合灰色不变。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: drawRectangle 透明度改常量（深度走颜色）

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`TreeMapCanvasView.drawRectangle`，约 474-485 行）

**Interfaces:**
- Consumes: Task 2 的 `depthColor`（已让块颜色承载深度）。
- Produces: `drawRectangle` 不再用大小调透明度，`baseOpacity` 改常量。

- [ ] **Step 1: drawRectangle 背景填充透明度改常量**

把 `drawRectangle` 内背景填充段（约 478-485 行）：

```swift
        // 绘制背景 - 高亮类型保持原色，其它降透
        let dimmed = highlightedFileType != nil && !isHighlighted(rectangle)
        let baseOpacity = isHovered ? 0.95 : 0.8
        let opacity = dimmed ? baseOpacity * 0.2 : baseOpacity
        context.fill(
            Path(rect),
            with: .color(rectangle.color.opacity(opacity))
        )
```

改为：

```swift
        // 绘制背景 - 颜色深度由 depthColor 承载(亮度通道)，此处透明度用常量；
        // 高亮类型保持原色，其它降透
        let dimmed = highlightedFileType != nil && !isHighlighted(rectangle)
        let baseOpacity: Double = isHovered ? 0.95 : 0.85
        let opacity = dimmed ? baseOpacity * 0.2 : baseOpacity
        context.fill(
            Path(rect),
            with: .color(rectangle.color.opacity(opacity))
        )
```

> 注：非 hover 由 0.8 提到 0.85（深度已走颜色，透明度更接近不透明让颜色本色显现）；hover 仍 0.95。dimmed 降透逻辑不变。

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: drawRectangle 透明度改常量，颜色深度走亮度通道

baseOpacity 非 hover 0.8→0.85，深度由 depthColor 承载，hover/dimmed 逻辑不变。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 新增 SidebarDualView（上下堆叠两区）

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`SidebarTabView` 定义处，约 863-906 行）

**Interfaces:**
- Consumes: `LegendSidebarView`（现有）、`DetailsSidebarView`（现有）。
- Produces: `struct SidebarDualView: View`（上下堆叠，无分页），供 Task 5 替换 `SidebarTabView` 调用点。本任务**保留** `SidebarTab`/`SidebarTabView` 定义不删（Task 5 删，避免本任务破坏现有调用点导致构建失败）。

- [ ] **Step 1: 在 SidebarTabView 之后插入 SidebarDualView**

在 `SidebarTabView` 结构体闭合 `}`（约 906 行）之后插入：

```swift
// MARK: - 侧栏上下堆叠两区（图例上、详情下，不分页）
struct SidebarDualView: View {
    let selectedNode: Binding<TreeNode?>
    let typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 上半：图例区（弹性高度，可滚动）
            LegendSidebarView(
                entries: typeBreakdown,
                highlightedFileType: highlightedFileType,
                onToggleHighlight: onToggleHighlight
            )
            Divider()
            // 下半：详情区（按内容，可滚动）
            DetailsSidebarView(
                selectedNode: selectedNode,
                fileSystemService: fileSystemService,
                scanRootURL: scanRootURL,
                onRequestDelete: onRequestDelete
            )
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }
}
```

> 注：`LegendSidebarView`/`DetailsSidebarView` 当前各自带 `.frame(width: 200)`。若两子视图都带 200 宽，外层 `SidebarDualView` 再设 200 会重复但无害。Task 5 会去掉两子视图的 `.frame(width:200)`，让宽度由 `SidebarDualView` 统一。本任务先不动子视图，构建应通过（重复 frame 无害）。

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`（SidebarDualView 未被引用，但需编译通过）

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 新增 SidebarDualView 上下堆叠两区

图例区上半、详情区下半同列堆叠，不分页。供 ContentView 替换分页侧栏。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: ContentView 组装 — 删分页、侧栏换 DualView、onTap 去跳详情、子视图去 width

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（ContentView 状态区 `sidebarTab`、Canvas `onTap`、侧栏调用点、`SidebarTab`/`SidebarTabView` 定义、`LegendSidebarView`/`DetailsSidebarView` 的 `.frame(width:200)`）

**Interfaces:**
- Consumes: Task 4 的 `SidebarDualView`。
- Produces: 完整 v0.3.2 侧栏（去分页上下堆叠）。

- [ ] **Step 1: 删 sidebarTab 状态**

在 ContentView 的 `@State` 区，删除：

```swift
    @State private var sidebarTab: SidebarTab = .legend
```

（约 26 行。grep `sidebarTab` 确认无其它引用后再删。）

- [ ] **Step 2: Canvas onTap 去掉 sidebarTab = .details**

把 Canvas `onTap` 闭包（约 150-153 行）：

```swift
                            onTap: { rectangle in
                                selectedNode = rectangle.node
                                sidebarTab = .details
                            },
```

改为：

```swift
                            onTap: { rectangle in
                                selectedNode = rectangle.node
                            },
```

- [ ] **Step 3: 侧栏调用点 SidebarTabView → SidebarDualView**

把侧栏块（约 229-243 行）：

```swift
                    if showLegend {
                        SidebarTabView(
                            sidebarTab: $sidebarTab,
                            selectedNode: $selectedNode,
                            typeBreakdown: typeBreakdown,
                            highlightedFileType: highlightedFileType,
                            onToggleHighlight: { type in
                                highlightedFileType = (highlightedFileType == type) ? nil : type
                            },
                            fileSystemService: fileSystemService,
                            scanRootURL: scanRootURL,
                            onRequestDelete: { _ in
                                showingDeleteConfirm = true
                            }
                        )
                    }
```

改为：

```swift
                    if showLegend {
                        SidebarDualView(
                            selectedNode: $selectedNode,
                            typeBreakdown: typeBreakdown,
                            highlightedFileType: highlightedFileType,
                            onToggleHighlight: { type in
                                highlightedFileType = (highlightedFileType == type) ? nil : type
                            },
                            fileSystemService: fileSystemService,
                            scanRootURL: scanRootURL,
                            onRequestDelete: { _ in
                                showingDeleteConfirm = true
                            }
                        )
                    }
```

- [ ] **Step 4: 删 SidebarTab 枚举与 SidebarTabView 定义**

删除整段（约 863-906 行）：

```swift
enum SidebarTab: Hashable {
    case legend
    case details
}

struct SidebarTabView: View {
    @Binding var sidebarTab: SidebarTab
    let selectedNode: Binding<TreeNode?>
    let typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarTab) {
                Text("图例").tag(SidebarTab.legend)
                Text("详情").tag(SidebarTab.details)
            }
            .pickerStyle(.segmented)
            .padding(8)

            switch sidebarTab {
            case .legend:
                LegendSidebarView(
                    entries: typeBreakdown,
                    highlightedFileType: highlightedFileType,
                    onToggleHighlight: onToggleHighlight
                )
            case .details:
                DetailsSidebarView(
                    selectedNode: selectedNode,
                    fileSystemService: fileSystemService,
                    scanRootURL: scanRootURL,
                    onRequestDelete: onRequestDelete
                )
            }
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }
}
```

（Task 4 的 `SidebarDualView` 保留。）

- [ ] **Step 5: LegendSidebarView 去 .frame(width: 200)**

把 `LegendSidebarView` 的 `body` 末尾（约 937-940 行）：

```swift
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }
}
```

改为（去 `.frame(width: 200)`，保留 background；宽度由 `SidebarDualView` 统一）：

```swift
        }
        .background(.regularMaterial)
    }
}
```

- [ ] **Step 6: DetailsSidebarView 去 .frame(width: 200)（若有）**

grep `frame(width: 200` 在 `DetailsSidebarView` 内。`DetailsSidebarView`（Task 4 of v0.3.1 改造）当前 `body` 末尾应为 `.padding(...)` 无 width frame——确认：

```bash
cd /Users/gwm/code/CubeCleaner && grep -n "frame(width: 200" CubeCleaner/ContentView.swift
```

若 `DetailsSidebarView` 无 `.frame(width:200)`，跳过本步。若有，删除该行（保留其它修饰符）。

- [ ] **Step 7: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

若报 `sidebarTab` 未定义，回查 Step 1 是否漏删引用（grep `sidebarTab`）。

- [ ] **Step 8: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ContentView 侧栏换 SidebarDualView 去分页

删 SidebarTab/SidebarTabView/sidebarTab，侧栏调用点改 SidebarDualView
上下堆叠两区，onTap 不再跳详情页，子视图去重复 width frame。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 文档订正与最终构建

**Files:**
- Modify: `README.md`（状态行 v0.3.1→v0.3.2、Features 补双区侧栏/类型内深度配色）
- Modify: `docs/Interface-Design.md`（3.1.1 说明行改上下堆叠两区、3.5.2 配色说明补类型内深度）

**Interfaces:** 无。

- [ ] **Step 1: README.md 状态行与 Features 更新**

把 `README.md` 状态行：

```
**当前状态：v0.3.1-beta，详情侧栏分页、移到废纸篓删除、钻取统计随根刷新可用。**
```

改为：

```
**当前状态：v0.3.2-beta，图例/详情同列双区、同类型内大小调深度配色可用。**
```

`## Features (v0.3.1)` 标题改为 `## Features (v0.3.2)`，并在 Features 列表追加 2 条（保留现有）：

```
- 🗂️ **图例/详情双区侧栏**: 图例上、详情下同列堆叠，同屏可见无需切换
- 🎨 **类型内深度配色**: 同类型下越大越深(调亮度)，以类型内最大块为基准
```

- [ ] **Step 2: Interface-Design.md 更新**

在 `docs/Interface-Design.md` 的 3.1.1 说明文字，把"右侧分页侧栏（图例/详情，可隐藏）；无 Inspector"改为"右侧双区侧栏（图例上/详情下，可隐藏）；无 Inspector"。

在 3.5.2 颜色表后追加说明：

```
（v0.3.2）同类型内按大小调亮度：以该类型在当前布局子树内的最大块为基准，
越大越接近原色(深)，越小越浅。文件夹固定色，不参与深度调节。
```

- [ ] **Step 3: 最终构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 4: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add README.md docs/Interface-Design.md
git -C /Users/gwm/code/CubeCleaner commit -m "docs: 同步 v0.3.2 双区侧栏/类型内深度配色到 README 与 Interface-Design

状态升 v0.3.2，Features 补双区侧栏/类型内深度，布局说明改上下堆叠，
配色表补类型内调亮度说明。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review 记录

- **Spec coverage**：spec §2 侧栏分两区 → Task 4+5；§2.2 SidebarDualView → Task 4；§2.3 调用点 + 删分页 → Task 5；§3 颜色深度调亮度 → Task 1（depthColor）+ Task 2（maxSizeByType + createLeafRectangle）+ Task 3（drawRectangle 透明度常量）；§3.3 数据流 maxSizeByType → Task 2；§3.4 depthColor → Task 1；§3.5 drawRectangle → Task 3；§4 文件清单全覆盖；§6 文档 → Task 6。无遗漏。
- **Placeholder scan**：无 TBD/TODO。Task 1 给出 NSColor 版本明确代码。Task 5 Step6 用 grep 条件判断（有则删无则跳），非占位。
- **Type consistency**：`depthColor(for node: TreeNode, maxSizeInType: Int64) -> Color`（Task 1 定义）在 Task 2 `createLeafRectangle` 调用一致；`maxSizeByType: [FileType: Int64]`（Task 2 定义）在 `findMaxSizeByType` 与 `createLeafRectangle` 一致；`SidebarDualView` 签名（Task 4：7 参数无 sidebarTab）在 Task 5 调用点一致。
- **跨任务构建**：Task 1-4 各自可独立构建（Task 4 新增未引用视图）。Task 5 是组装点，首个改动调用点的任务，构建须全绿。
