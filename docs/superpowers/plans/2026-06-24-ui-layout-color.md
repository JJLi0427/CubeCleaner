# CubeCleaner v0.3 页面布局与配色优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把统计提到顶部醒目位置、导航加独立返回按钮、换高饱和调色板、新增类型占比比例条与可点击高亮的图例侧栏。

**Architecture:** 纯视觉层改造，不重写布局算法。数据层加 `folderCount` 统计与 `typeBreakdown(for:)` 聚合函数；视图层重排 `ContentView` 根 `VStack` 为四层（工具栏/统计条/导航条/主内容）+ 右侧图例侧栏，并给 `TreeMapCanvasView` 加高亮降透能力。

**Tech Stack:** Swift 5.0, SwiftUI, macOS 15.5 deployment target, Canvas rendering, `ByteCountFormatter`.

**Repo note:** 仓库无 XCTest target。本计划以 `./build.sh build` 通过作为每任务验收门槛（替代单元测试）；`FileSystemService` 与 `typeBreakdown` 的纯逻辑改动以 `swift -typecheck` 片段 + 构建通过为准。所有 `git` 命令须 `git -C /Users/gwm/code/CubeCleaner`（工作目录是 `/Users/gwm`，不在仓库内）。

## Global Constraints

- 部署目标 macOS 15.5、Swift 5.0（与现有 Xcode 工程一致）。
- 不重写 `BinaryTreeMapCalculator` 布局算法。
- 不做亮/暗模式分别调色；颜色用固定高饱和 RGB。
- 侧栏宽度固定 200pt，不做拖拽。
- 比例条只做整条 tooltip，不做区段命中。
- 颜色 RGB 值（sRGB 0-1）逐字取自 spec：document `(0.039, 0.518, 1.0)` #0A84FF；image `(0.188, 0.820, 0.345)` #30D158；video `(1.0, 0.271, 0.227)` #FF453A；audio `(0.749, 0.353, 0.949)` #BF5AF2；archive `(1.0, 0.624, 0.039)` #FF9F0A；application `(0.392, 0.824, 1.0)` #64D2FF；system `(1.0, 0.839, 0.039)` #FFD60A；other `(1.0, 0.216, 0.373)` #FF375F；文件夹 `(0.251, 0.784, 0.878)` #40C8E0。
- 提交信息中文，结尾含 `Co-Authored-By: Claude <noreply@anthropic.com>`。
- 所有改动在 `ljj/rebuild` 分支上提交。

---

## File Structure

- `CubeCleaner/Service/CubeCleanerBackend.swift` — 改 `ColorSchemeManager`（高饱和调色板 + `typeBreakdown`）、`FileSystemService`（加 `folderCount`）。
- `CubeCleaner/ContentView.swift` — 重排根布局，新增 `StatsBarView`/`MetricBlock`/`TypeRatioBarView`/`NavigationBarView`/`LegendSidebarView`/`LegendRow`，改 `TreeMapCanvasView` 高亮。

任务依赖：Task 1（数据层调色板）→ Task 2（folderCount）→ Task 3（typeBreakdown 聚合）→ Task 4（StatsBarView）→ Task 5（TypeRatioBarView）→ Task 6（NavigationBarView 返回按钮）→ Task 7（LegendSidebarView）→ Task 8（TreeMapCanvasView 高亮）→ Task 9（ContentView 组装 + 删底部重复统计）→ Task 10（最终构建 + 文档订正）。

---

### Task 1: ColorSchemeManager 高饱和调色板

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`ColorSchemeManager` 类，约 436-488 行）

**Interfaces:**
- Consumes: 现有 `FileType` 枚举、`TreeNode`。
- Produces: `fileTypeColors: [FileType: Color]`、`directoryColor: Color`、`color(for:)`/`adjustedColor(for:maxSize:)` 签名不变（仅改色值），后续 Task 3 依赖 `ColorSchemeManager.shared`。

- [ ] **Step 1: 替换 `fileTypeColors` 与 `directoryColor`**

把 `ColorSchemeManager` 内：

```swift
    private let fileTypeColors: [FileType: Color] = [
        .document: .blue,
        .image: .green,
        .video: .red,
        .audio: .purple,
        .archive: .orange,
        .application: .gray,
        .system: .yellow,
        .other: Color(.systemGray),
    ]

    /// 文件夹专用颜色
    private let directoryColor: Color = .brown
```

替换为：

```swift
    /// 高饱和调色板（v0.3）— 固定 RGB，不做亮/暗分别调色
    private let fileTypeColors: [FileType: Color] = [
        .document: Color(red: 0.039, green: 0.518, blue: 1.0),     // #0A84FF
        .image: Color(red: 0.188, green: 0.820, blue: 0.345),      // #30D158
        .video: Color(red: 1.0, green: 0.271, blue: 0.227),        // #FF453A
        .audio: Color(red: 0.749, green: 0.353, blue: 0.949),      // #BF5AF2
        .archive: Color(red: 1.0, green: 0.624, blue: 0.039),      // #FF9F0A
        .application: Color(red: 0.392, green: 0.824, blue: 1.0),  // #64D2FF
        .system: Color(red: 1.0, green: 0.839, blue: 0.039),       // #FFD60A
        .other: Color(red: 1.0, green: 0.216, blue: 0.373),        // #FF375F
    ]

    /// 文件夹专用颜色（高饱和深青）
    private let directoryColor: Color = Color(red: 0.251, green: 0.784, blue: 0.878)  // #40C8E0
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ColorSchemeManager 换高饱和调色板

8 类型色与文件夹色改为固定高饱和 RGB，保留大小→透明度映射。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: FileSystemService 加 folderCount

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`FileSystemService` 类：约 989 行 `@Published` 区、约 1027 行 `filesScanned = 0`、约 1166 行 `if item.isDirectory`、约 1210 行附近 fallback 同处）

**Interfaces:**
- Consumes: 现有扫描流程。
- Produces: `@Published var folderCount: Int`，供 Task 4 统计条读取。

- [ ] **Step 1: 加 `folderCount` Published 属性**

在 `FileSystemService` 的 `@Published var filesScanned: Int = 0` 这一行后插入：

```swift
    @Published var folderCount: Int = 0
```

- [ ] **Step 2: scanDirectory(at:) 重置 folderCount**

找到 `scanDirectory(at url: URL)` 内 `filesScanned = 0`（约 1027 行），在其下一行加：

```swift
        folderCount = 0
```

（与 `filesScanned = 0`、`totalSize = 0` 等重置放一起，保持风格。）

- [ ] **Step 3: processBatch 累计文件夹**

在 `processBatch` 内 `if item.isDirectory {` 分支（约 1166 行）：

```swift
            // 递归扫描子目录
            if item.isDirectory {
                folderCount += 1
                await scanRecursively(node: childNode, currentDepth: currentDepth + 1)
            }
```

- [ ] **Step 4: scanRecursivelyFallback 累计文件夹**

在 `scanRecursivelyFallback` 内对应 `if item.isDirectory {` 分支（约 1210 行附近，找到 fallback 中递归扫描子目录处）加 `folderCount += 1`：

```swift
                    if item.isDirectory {
                        folderCount += 1
                        await scanRecursivelyFallback(node: childNode, currentDepth: currentDepth + 1)
                    }
```

先用 grep 定位确切位置：
```bash
grep -n "if item.isDirectory" CubeCleaner/Service/CubeCleanerBackend.swift
```
对 fallback 的那处（`scanRecursivelyFallback` 方法体内的）加 `folderCount += 1`。

- [ ] **Step 5: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: FileSystemService 统计 folderCount

扫描时累计目录数，供顶部统计条显示。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: ColorSchemeManager 加 typeBreakdown 聚合

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`ColorSchemeManager` 类内，Task 1 改过的区域之后）

**Interfaces:**
- Consumes: `FileType.from(extension:)`、`TreeNode`。
- Produces: `struct TypeBreakdownEntry`、`func typeBreakdown(for node: TreeNode) -> [TypeBreakdownEntry]`，供 Task 5 比例条与 Task 7 图例共用。

- [ ] **Step 1: 在 `ColorSchemeManager` 类内末尾（`adjustedColor` 方法后、类闭合 `}` 前）插入聚合函数与结构体**

在 `ColorSchemeManager` 类内 `adjustedColor(for:maxSize:)` 方法之后插入：

```swift
    /// 类型占比条目（供统计条比例条与图例侧栏共用）
    struct TypeBreakdownEntry: Identifiable {
        let id = UUID()
        let type: FileType
        let size: Int64
        let color: Color
        var ratio: CGFloat {      // size / total；total=0 时外部不渲染
            total > 0 ? CGFloat(size) / CGFloat(total) : 0
        }
        let total: Int64
    }

    /// 聚合 node 子树所有叶子文件，按 FileType 累加 item.size。
    /// 文件夹不计入（避免与子文件重复）。返回 8 类型（含 size=0），按 size 降序。
    func typeBreakdown(for node: TreeNode) -> [TypeBreakdownEntry] {
        var sizes: [FileType: Int64] = [:]
        for type in FileType.allCases { sizes[type] = 0 }

        func traverse(_ current: TreeNode) {
            if current.item.isDirectory {
                for child in current.children { traverse(child) }
            } else {
                let ft = FileType.from(extension: current.item.fileExtension)
                sizes[ft, default: 0] += current.item.size
            }
        }
        traverse(node)

        let total = sizes.values.reduce(Int64(0), +)
        return FileType.allCases
            .map { TypeBreakdownEntry(type: $0, size: sizes[$0] ?? 0, color: color(for: $0), total: total) }
            .sorted { $0.size > $1.size }
    }
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ColorSchemeManager 加 typeBreakdown 聚合

遍历子树按 FileType 累加叶子文件大小，返回 8 类型降序条目，
供统计条比例条与图例侧栏共用。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: StatsBarView 与 MetricBlock

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（文件末尾 `BreadcrumbView` 之后、`#Preview` 之前插入新视图）

**Interfaces:**
- Consumes: `fileSystemService.rootNode`、`fileSystemService.filesScanned`、`fileSystemService.folderCount`、`fileSystemService.totalSize`、`fileSystemService.isScanning`。
- Produces: `struct StatsBarView: View`、`struct MetricBlock: View`，供 Task 9 组装。

- [ ] **Step 1: 在 ContentView.swift 末尾插入 StatsBarView 与 MetricBlock**

在 `BreadcrumbView` 结构体闭合 `}` 之后、`#Preview {` 之前插入：

```swift
// MARK: - 统计条视图
struct StatsBarView: View {
    let totalSize: Int64
    let fileCount: Int
    let folderCount: Int
    let isScanning: Bool

    var body: some View {
        HStack(spacing: 24) {
            MetricBlock(
                icon: "externaldrive.fill",
                value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                label: "总大小"
            )
            MetricBlock(
                icon: "doc.fill",
                value: "\(fileCount)",
                label: "文件"
            )
            MetricBlock(
                icon: "folder.fill",
                value: "\(folderCount)",
                label: "文件夹"
            )
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
}

struct MetricBlock: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`（新视图尚未被引用，但需编译通过）

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 新增 StatsBarView 与 MetricBlock

顶部统计条三指标(总大小/文件数/文件夹数)大号显示组件。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: TypeRatioBarView 内联比例条

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`StatsBarView` 之后插入）

**Interfaces:**
- Consumes: `ColorSchemeManager.TypeBreakdownEntry`（Task 3 产出）。
- Produces: `struct TypeRatioBarView: View`，供 Task 9 装入统计条第二行。

- [ ] **Step 1: 在 StatsBarView/MetricBlock 之后插入 TypeRatioBarView**

```swift
// MARK: - 类型占比比例条
struct TypeRatioBarView: View {
    let entries: [ColorSchemeManager.TypeBreakdownEntry]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.quaternary)
                HStack(spacing: 0) {
                    ForEach(entries.filter { $0.size > 0 }) { entry in
                        entry.color
                            .frame(width: geo.size.width * entry.ratio)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 10)
        .help(tooltipText)
    }

    /// 整条 tooltip（首版不分区段命中）
    private var tooltipText: String {
        guard !entries.isEmpty else { return "无数据" }
        let total = entries.first?.total ?? 0
        return entries
            .filter { $0.size > 0 }
            .map { e in
                let pct = total > 0 ? Int(Double(e.size) / Double(total) * 100) : 0
                return "\(e.type.displayName) \(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) \(pct)%"
            }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 新增 TypeRatioBarView 内联比例条

全宽多色 Capsule，按类型大小分宽度，整条 tooltip 显示各类型占比。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: NavigationBarView 返回按钮 + BreadcrumbView

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`TypeRatioBarView` 之后插入；`BreadcrumbView` 保持不变）

**Interfaces:**
- Consumes: 现有 `BreadcrumbView`、`currentRoot`、`rootNode`。
- Produces: `struct NavigationBarView: View`，含返回回调；供 Task 9 组装。

- [ ] **Step 1: 在 TypeRatioBarView 之后插入 NavigationBarView**

```swift
// MARK: - 导航条视图（返回按钮 + 面包屑）
struct NavigationBarView: View {
    let currentRoot: TreeNode?
    let rootNode: TreeNode?
    let onBack: () -> Void
    let onSelectBreadcrumb: (TreeNode) -> Void

    /// 是否在根目录（返回按钮禁用条件）
    private var isAtRoot: Bool {
        currentRoot == nil || currentRoot?.id == rootNode?.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("返回上一级", systemImage: "chevron.backward")
            }
            .buttonStyle(.bordered)
            .disabled(isAtRoot)

            Divider()
                .frame(height: 16)

            BreadcrumbView(currentRoot: currentRoot, onSelect: onSelectBreadcrumb)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }
}
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 新增 NavigationBarView 返回按钮+面包屑

返回上一级独立按钮，根目录禁用；面包屑沿用现有逻辑。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: LegendSidebarView 与 LegendRow

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`NavigationBarView` 之后插入）

**Interfaces:**
- Consumes: `ColorSchemeManager.TypeBreakdownEntry`、`FileType`。
- Produces: `struct LegendSidebarView: View`，点击切换 `highlightedFileType`；供 Task 9 组装。

- [ ] **Step 1: 在 NavigationBarView 之后插入 LegendSidebarView 与 LegendRow**

```swift
// MARK: - 图例侧栏视图
struct LegendSidebarView: View {
    let entries: [ColorSchemeManager.TypeBreakdownEntry]
    let highlightedFileType: FileType?
    let onToggleHighlight: (FileType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("类型分布")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(entries.filter { $0.size > 0 }) { entry in
                        LegendRow(
                            entry: entry,
                            isHighlighted: highlightedFileType == entry.type
                        )
                        .onTapGesture { onToggleHighlight(entry.type) }
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }
}

struct LegendRow: View {
    let entry: ColorSchemeManager.TypeBreakdownEntry
    let isHighlighted: Bool

    var body: some View {
        let pct = entry.total > 0 ? Int(Double(entry.size) / Double(entry.total) * 100) : 0
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isHighlighted ? Color.primary : Color.clear, lineWidth: 2)
                )
            Text(entry.type.displayName)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text("\(pct)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
}
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 新增 LegendSidebarView 与 LegendRow

右侧图例侧栏，按类型大小降序列出色块/名称/大小/百分比，
点击切换该类型高亮。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: TreeMapCanvasView 高亮降透

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`TreeMapCanvasView` 结构体：约 339 行起、`drawRectangle` 约 401 行）

**Interfaces:**
- Consumes: `FileType.from(extension:)`、`highlightedFileType`。
- Produces: `TreeMapCanvasView` 新增 `highlightedFileType: FileType?` 参数，绘制时对非高亮矩形降透。

- [ ] **Step 1: 给 TreeMapCanvasView 加 highlightedFileType 属性**

把 `TreeMapCanvasView` 的属性块：

```swift
struct TreeMapCanvasView: View {
    let rectangles: [TreeMapRectangle]
    let onTap: (TreeMapRectangle) -> Void
    let onLongPress: (TreeMapRectangle) -> Void
    let onDoubleTap: (TreeMapRectangle) -> Void

    @State private var hoveredRectangle: TreeMapRectangle?
```

改为：

```swift
struct TreeMapCanvasView: View {
    let rectangles: [TreeMapRectangle]
    let highlightedFileType: FileType?
    let onTap: (TreeMapRectangle) -> Void
    let onLongPress: (TreeMapRectangle) -> Void
    let onDoubleTap: (TreeMapRectangle) -> Void

    @State private var hoveredRectangle: TreeMapRectangle?
```

- [ ] **Step 2: drawRectangle 内按高亮状态降透**

把 `drawRectangle` 开头的背景填充：

```swift
        // 绘制背景
        context.fill(
            Path(rect),
            with: .color(rectangle.color.opacity(isHovered ? 0.95 : 0.8))
        )
```

改为：

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

- [ ] **Step 3: 在 drawRectangle 内或 TreeMapCanvasView 内加 isHighlighted 辅助方法**

在 `TreeMapCanvasView` 内 `drawRectangle` 之前加：

```swift
    /// 当前矩形是否属于高亮类型（文件夹在存在高亮时视为不高亮）
    private func isHighlighted(_ rectangle: TreeMapRectangle) -> Bool {
        guard let highlightedFileType else { return true }
        if rectangle.node.item.isDirectory { return false }
        let ft = FileType.from(extension: rectangle.node.item.fileExtension)
        return ft == highlightedFileType
    }
```

- [ ] **Step 4: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: 编译会因 `TreeMapCanvasView(highlightedFileType:)` 调用处缺失参数而失败 —— 这是预期的，本任务暂不更新调用点（Task 9 会更新）。**但若报其它错误需修复。** 若仅报"missing argument highlightedFileType"，视为通过本步骤，继续 Task 9。

> 注：若希望每任务可独立构建，可临时在 Task 9 之前的调用点先补 `highlightedFileType: nil`。本计划选择在 Task 9 统一处理调用点，因此 Task 8 末尾构建可能因调用点报错——以"无新增编译错误、仅调用点缺参"为准。

- [ ] **Step 5: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: TreeMapCanvasView 高亮类型降透

新增 highlightedFileType 参数，非高亮类型矩形降至 20% 透明度，
文件夹在有高亮时统一降透。调用点在后续任务统一更新。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: ContentView 组装四层布局 + 侧栏 + 删底部重复统计

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（根 `body` VStack、工具栏、`currentRoot`/状态区、`updateLayoutOptimized`、`TreeMapCanvasView` 调用点、底部状态栏）

**Interfaces:**
- Consumes: Task 1-8 全部产出。
- Produces: 完整 v0.3 页面。

- [ ] **Step 1: ContentView 加新状态**

在 `ContentView` 的 `@State private var currentRoot: TreeNode?` 附近（约 17 行）加：

```swift
    @State private var showLegend: Bool = true
    @State private var highlightedFileType: FileType? = nil
    @State private var typeBreakdown: [ColorSchemeManager.TypeBreakdownEntry] = []
```

- [ ] **Step 2: updateLayoutOptimized 末尾刷新 typeBreakdown**

在 `updateLayoutOptimized` 内 `withAnimation { rectangles = newRectangles; isLayouting = false }` 块内追加刷新（与 rectangles 同在主线程赋值）：

```swift
            withAnimation(.easeOut(duration: 0.25)) {
                rectangles = newRectangles
                isLayouting = false
                typeBreakdown = ColorSchemeManager.shared.typeBreakdown(for: rootNode)
            }
```

- [ ] **Step 3: 工具栏加"边栏"切换按钮**

在工具栏 `HStack` 内 `Spacer()` 与状态信息 `VStack` 之间（约 47 行 Spacer 之后），插入边栏切换按钮；并把原状态信息 `VStack`（已选目录 + 文件总数/总大小那两行 `.caption`/`.caption2`）删除（统计已上移顶部）：

原：
```swift
                Spacer()

                // 状态信息
                VStack(alignment: .trailing, spacing: 2) {
                    if let selectedPath = selectedPath {
                        Text("已选择: \(selectedPath.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if fileSystemService.rootNode != nil {
                        Text(
                            "文件总数: \(fileSystemService.filesScanned) | 总大小: \(ByteCountFormatter.string(fromByteCount: fileSystemService.totalSize, countStyle: .file))"
                        )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
```

改为：

```swift
                Spacer()

                if let selectedPath = selectedPath {
                    Text("已选择: \(selectedPath.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Button {
                    showLegend.toggle()
                } label: {
                    Image(systemName: showLegend ? "sidebar.left" : "sidebar.right")
                }
                .buttonStyle(.bordered)
                .help(showLegend ? "隐藏类型图例" : "显示类型图例")
```

- [ ] **Step 4: 在 Divider() 后、主内容 GeometryReader 前插入统计条与导航条**

找到工具栏 `.padding()` + `.background(...)` 后的第一个 `Divider()`（约 69 行），在其后插入统计条 + Divider + 导航条。同时把主内容区从单 `GeometryReader { ZStack {...} }` 改为 `HStack`（Canvas + 侧栏），并把原浮于 Canvas 顶部的 `BreadcrumbView` VStack 替换为 `NavigationBarView`。

把现有主内容区起始：

```swift
            Divider()

            // 主内容区域
            GeometryReader { geometry in
                ZStack {
                    Color(.controlBackgroundColor)
```

改为：

```swift
            Divider()

            // 统计条
            if fileSystemService.rootNode != nil || fileSystemService.isScanning {
                StatsBarView(
                    totalSize: fileSystemService.totalSize,
                    fileCount: fileSystemService.filesScanned,
                    folderCount: fileSystemService.folderCount,
                    isScanning: fileSystemService.isScanning
                )
                TypeRatioBarView(entries: typeBreakdown)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(Color(.controlBackgroundColor))
                Divider()
            }

            // 导航条
            NavigationBarView(
                currentRoot: currentRoot,
                rootNode: fileSystemService.rootNode,
                onBack: {
                    currentRoot = currentRoot?.parent
                    Task { await updateLayoutOptimized(size: CGSize(width: 0, height: 0)) }
                },
                onSelectBreadcrumb: { node in
                    currentRoot = node
                    Task { await updateLayoutOptimized(size: CGSize(width: 0, height: 0)) }
                }
            )
            .zIndex(1)

            Divider()

            // 主内容区域：Canvas + 图例侧栏
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ZStack {
                        Color(.controlBackgroundColor)
```

> ⚠️ `onBack`/`onSelectBreadcrumb` 里的 `CGSize(width: 0, height: 0)` 是占位 —— 必须用真实的 `geometry.size`。但闭包在 `GeometryReader` 外部已捕获不到 geometry。**改用现有代码同一处的写法**：现有 `BreadcrumbView` 的 `onSelect` 闭包内是 `Task { await updateLayoutOptimized(size: geometry.size) }`。所以此处应改为不内联在 GeometryReader 外 —— 见 Step 5 调整：导航条放回 GeometryReader 内部。

**修正（Step 4 收尾）**：为避免 `geometry` 捕获问题，把统计条放在 GeometryReader 外，但**导航条放回 GeometryReader 内的 ZStack 顶部**（沿用现有 `BreadcrumbView` 浮于 Canvas 的位置，仅替换为 `NavigationBarView`）。即 Step 4 实际落地为：

- 统计条 + 比例条放在 `Divider()` 后、`GeometryReader` 前（它们不需要 geometry）。
- `NavigationBarView` 不放 GeometryReader 外；而是替换原 ZStack 内顶部的 `BreadcrumbView` VStack（约 76-92 行那段 `VStack { BreadcrumbView(...) ... }.zIndex(1)`）。

替换原 ZStack 内顶部：

```swift
                    // 面包屑导航 - 浮于 TreeMap 顶部，不挤压可视空间
                    VStack {
                        BreadcrumbView(
                            currentRoot: currentRoot,
                            onSelect: { node in
                                currentRoot = node
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        Spacer()
                    }
                    .zIndex(1)
```

为：

```swift
                    // 导航条（返回按钮 + 面包屑）- 浮于 TreeMap 顶部
                    VStack(spacing: 0) {
                        NavigationBarView(
                            currentRoot: currentRoot,
                            rootNode: fileSystemService.rootNode,
                            onBack: {
                                currentRoot = currentRoot?.parent
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            },
                            onSelectBreadcrumb: { node in
                                currentRoot = node
                                Task {
                                    await updateLayoutOptimized(size: geometry.size)
                                }
                            }
                        )
                        Spacer()
                    }
                    .zIndex(1)
```

（统计条已移到 GeometryReader 外，故 ZStack 内顶部不再需要那段 `.background(.ultraThinMaterial)` 包裹的 BreadcrumbView；`NavigationBarView` 自带 material 背景。）

- [ ] **Step 5: 主内容 ZStack 改 HStack(Canvas + 侧栏)，更新 TreeMapCanvasView 调用点**

把主内容 `GeometryReader { geometry in ZStack { ... } ... }` 结构改为 `GeometryReader { geometry in HStack(spacing: 0) { ZStack { ...Canvas... }; if showLegend { LegendSidebarView(...) } } ... }`。

具体：在原 `ZStack { Color(...)` 之后、Canvas 代码块之后、`} else if fileSystemService.isScanning {` 之前不破坏逻辑，而是把整个 `GeometryReader` 内容包进 `HStack`，并在 Canvas 部分末尾、`.onAppear`/`.onChange` 之前插入侧栏。

更稳妥：在 `TreeMapCanvasView(...)` 调用处补 `highlightedFileType: highlightedFileType` 参数，并在 `GeometryReader` 内 `ZStack` 外层包 `HStack`。

找到 `TreeMapCanvasView` 调用处（约 110-137 行 `TreeMapCanvasView( rectangles:..., onTap:..., onLongPress:..., onDoubleTap:...)`），加 `highlightedFileType: highlightedFileType,`：

```swift
                        TreeMapCanvasView(
                            rectangles: rectangles,
                            highlightedFileType: highlightedFileType,
                            onTap: { rectangle in
                                selectedNode = rectangle.node
                                showingDetails = true
                            },
                            onLongPress: { rectangle in
                                NSWorkspace.shared.selectFile(
                                    rectangle.node.item.path.path,
                                    inFileViewerRootedAtPath: ""
                                )
                            },
                            onDoubleTap: { rectangle in
                                // 目录可双击进入；聚合的"其他"块也可双击钻取内部小文件
                                let node = rectangle.node
                                if node.isAggregated || node.item.isDirectory {
                                    currentRoot = node
                                    Task {
                                        await updateLayoutOptimized(size: geometry.size)
                                    }
                                }
                            }
                        )
```

然后把 `GeometryReader { geometry in` 的直接子节点（`ZStack { ... }` 以及其后的 `.onAppear`/`.onChange`/详情面板）改为：外层 `HStack(spacing: 0) { ZStack { ...原内容... } ; if showLegend { LegendSidebarView(...) } }`，原 `.onAppear` 等修饰符挂在 `HStack` 上。

实现要点（让实现者据此改写）：
1. `GeometryReader { geometry in HStack(spacing: 0) {`
2. 第一项：原 `ZStack { ... }`（Canvas + 导航条浮层 + 详情面板），保持原有 `.onAppear`/`.onChange`/详情面板等修饰符移到 `HStack` 上。
3. 第二项：`if showLegend { LegendSidebarView(entries: typeBreakdown, highlightedFileType: highlightedFileType, onToggleHighlight: { type in highlightedFileType = (highlightedFileType == type) ? nil : type }) }`
4. 关闭 `HStack`。

- [ ] **Step 6: 删除底部状态栏的重复统计**

找到底部状态栏（约 221-241 行）：

```swift
            // 状态栏
            HStack {
                if let rootNode = fileSystemService.rootNode {
                    Text(
                        "总大小: \(ByteCountFormatter.string(fromByteCount: rootNode.totalSize, countStyle: .file))"
                    )
                    Spacer()
                    Text("文件数: \(fileSystemService.filesScanned)")
                } else if let errorMessage = fileSystemService.errorMessage {
                    Text("错误: \(errorMessage)")
                        .foregroundColor(.red)
                    Spacer()
                } else {
                    Text("就绪")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("CubeCleaner v0.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
```

改为（仅留错误/就绪/版本，去掉重复的总大小与文件数）：

```swift
            // 状态栏（统计已上移顶部，此处仅留错误/就绪/版本）
            HStack {
                if let errorMessage = fileSystemService.errorMessage {
                    Text("错误: \(errorMessage)")
                        .foregroundColor(.red)
                    Spacer()
                } else if fileSystemService.rootNode == nil {
                    Text("就绪")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Spacer()
                }
                Text("CubeCleaner v0.3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
```

- [ ] **Step 7: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

若报 `geometry` 捕获错误，确认导航条仍在 `GeometryReader` 内（Step 4 修正版）。

- [ ] **Step 8: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ContentView 组装 v0.3 四层布局+图例侧栏

顶部统计条+类型比例条，导航条返回按钮+面包屑浮于 Canvas，
主内容 Canvas+可隐藏图例侧栏，点击类型高亮降透非匹配矩形，
删除底部重复统计，版本号升至 v0.3。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: 文档订正与最终构建

**Files:**
- Modify: `README.md`（状态行 v0.2→v0.3、Features 补统计/图例/高亮）
- Modify: `docs/Interface-Design.md`（3.1.1 实际布局更新为四层+侧栏、3.5.3 交互补图例高亮、配色表更新）
- Modify: `NEXT_STEPS.md`（如有 v0.3 相关条目更新）

**Interfaces:** 无。

- [ ] **Step 1: README.md 状态行与 Features 更新**

把 `README.md` 第 5 行：

```
**当前状态：v0.2-beta，基础扫描与 TreeMap 可视化可用。**
```

改为：

```
**当前状态：v0.3-beta，顶部统计条、类型占比图例、高饱和配色与返回导航可用。**
```

在 `## Features (v0.2)` 标题改为 `## Features (v0.3)`，并在 Features 列表内追加（保留现有 7 条，新增 3 条）：

```
- 📊 **顶部统计条**: 总大小/文件数/文件夹数大号显示 + 类型占比比例条
- 🗂️ **类型图例侧栏**: 右侧列各类型大小占比，点击高亮 TreeMap 中该类型矩形
- 🎨 **高饱和配色**: 8 文件类型 + 文件夹采用高饱和 RGB，颜色丰富易辨
- ↩️ **返回导航**: 独立"返回上一级"按钮，根目录自动禁用
```

（调整列表项以保持原 markdown 缩进风格。）

- [ ] **Step 2: Interface-Design.md 3.1.1 布局图更新**

把 `docs/Interface-Design.md` 的 3.1.1 ASCII 布局图替换为四层 + 侧栏结构：

```
┌─────────────────────────────────────────────────────────────┐
│ [选择文件夹] [取消扫描]        已选择:xxx          [边栏▦] │ 工具栏
├─────────────────────────────────────────────────────────────┤
│ 💾 总大小 xxx   📄 文件 xxx   📁 文件夹 xxx               │ 统计条
│ [■■■■■■■■■■■■■■■■■■■■■■■■■■] 类型比例条                    │
├─────────────────────────────────────────────────────────────┤
│ ←返回上一级   根 › 子目录 › ...                            │ 导航条
├──────────────────────────────────────────┬──────────────────┤
│ ┌──────── TreeMap Canvas ──────────────┐ │ 类型分布         │
│ │  ┌─────┐ ┌──┐ ┌─────────┐            │ │ ■ 图片 xxx 42%  │
│ │  │     │ │  │ │         │            │ │ ■ 视频 xxx 28%  │
│ │  └─────┘ └──┘ └─────────┘            │ │ ■ 文档 xxx  8%  │
│ │  ┌──────────────────────┐ [其他 N 项] │ │ ...             │
│ │  │                      │             │ └──────────────────┘
│ │  └──────────────────────┘             │                   │
│ └────────────────────────────────────────┘                   │
├─────────────────────────────────────────────────────────────┤
│                                  CubeCleaner v0.3           │ 状态栏
└─────────────────────────────────────────────────────────────┘
```

并更新 3.1.1 下方的说明文字：把"无 Sidebar / Inspector 双侧栏（计划中）"改为"右侧类型图例侧栏（可隐藏）；无 Inspector"。

- [ ] **Step 3: Interface-Design.md 3.5.3 交互与配色更新**

在 3.5.3 "#### 3.5.3 Interactive Elements (v0.2 已实现)" 标题改为 `(v0.3 已实现)`，交互列表追加：

```
- **点击图例类型**: 高亮 TreeMap 中该类型矩形，其它降至 20% 透明度；再点取消
- **返回上一级**: 独立按钮，根目录禁用
```

把 3.5.2 "##### By File Type" 的颜色表数值更新为 v0.3 高饱和值：

```
Documents:    Electric Blue (#0A84FF)
Images:       Green (#30D158)
Videos:       Coral Red (#FF453A)
Audio:        Purple (#BF5AF2)
Archives:     Amber (#FF9F0A)
Applications: Cyan (#64D2FF)
System:       Yellow (#FFD60A)
Other:        Pink (#FF375F)
Folders:      Teal (#40C8E0)
```

- [ ] **Step 4: 最终构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add README.md docs/Interface-Design.md
git -C /Users/gwm/code/CubeCleaner commit -m "docs: 同步 v0.3 布局/配色/交互到 README 与 Interface-Design

状态升 v0.3，Features 补统计条/图例/高饱和/返回导航，
布局图改四层+侧栏，配色表换高饱和值，交互补图例高亮。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review 记录

- **Spec coverage**：spec §2 布局 → Task 9；§3.1 工具栏边栏按钮 → Task 9 Step3；§3.2 统计条 → Task 4；§3.3 导航条返回 → Task 6+9；§3.4 图例侧栏 → Task 7+9；§3.5 比例条 → Task 5；§4.1 调色板 → Task 1；§4.2 folderCount → Task 2；§4.3 typeBreakdown → Task 3；§5 高亮 → Task 8+9；§6 状态 → Task 9 Step1/2；§7 文件清单全覆盖；§9 文档 → Task 10。无遗漏。
- **Placeholder scan**：无 TBD/TODO。Task 8 Step4 已显式标注"调用点缺参属预期"而非占位。Task 9 Step4/5 给出了确切改写方式。
- **Type consistency**：`TypeBreakdownEntry`（Task 3 定义）在 Task 5/7/9 一致使用 `ColorSchemeManager.TypeBreakdownEntry`；`highlightedFileType: FileType?`（Task 8 定义）在 Task 7/9 一致；`folderCount`（Task 2）在 Task 4/9 一致。
