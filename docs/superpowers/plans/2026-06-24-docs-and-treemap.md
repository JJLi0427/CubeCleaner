# CubeCleaner 文档更新 + TreeMap 算法优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把过时文档改写成与 v0.2 代码一致，重列下一步计划，并用"聚合其他块 + 双击导航"优化 TreeMap 消除过细矩形。

**Architecture:** 保留现有二分布局算法，改造 `getValidChildren` 把小文件聚合成虚拟"其他"节点（面积守恒），在 ContentView 引入 `currentRoot` 支持双击进入子目录（长尾自然展开）+ 面包屑返回。文档全部照实记录现状。SwiftUI + Canvas 渲染不变。

**Tech Stack:** Swift 5.9, SwiftUI, macOS 13.0+, Xcode 15, `getattrlistbulk` (Darwin)

## Global Constraints

- macOS 13.0 (Ventura) 最低部署目标。
- Swift 5.9 / Xcode 15。
- 构建命令：`./build.sh clean && ./build.sh build`，必须通过。
- 文档语言：中文（与现有文档一致）。
- 不更换布局算法为 Squarified，保留二分法。
- 不改扫描主线程问题、不拆分大文件、不补测试、不做删除功能——这些只记入 NEXT_STEPS 计划，不在本计划实施。
- 阈值常量：`aggregateRatio = 0.005`（0.5%），`minVisibleSize = 24`（保留现有）。
- 提交信息用中文描述 + `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾。
- 每个文件引用用 markdown 链接格式（VSCode 可点击）。

## File Structure

**文档（重写）**
- [README.md](README.md) — 修正 Roadmap、结构图、LICENSE 状态。
- [docs/Requirements.md](docs/Requirements.md) — 每条需求加状态标记。
- [docs/Interface-Design.md](docs/Interface-Design.md) — 改成实际布局，未实现项移到"计划中"。
- [docs/Programming-Design.md](docs/Programming-Design.md) — 删虚构 MVVM，照实描述 3 文件。
- [NEXT_STEPS.md](NEXT_STEPS.md) — 重写为 P0/P1/P2 三层。

**代码（改动）**
- [CubeCleaner/Service/CubeCleanerBackend.swift](CubeCleaner/Service/CubeCleanerBackend.swift) — `getValidChildren` 聚合逻辑、虚拟"其他"节点、`TreeMapRectangle` 加 `isAggregated` 标记。
- [CubeCleaner/ContentView.swift](CubeCleaner/ContentView.swift) — `currentRoot` 状态、双击导航、`BreadcrumbView`、悬停复活、删死代码 `TreeMapRectangleView`。

---

## Task 1: TreeMap 聚合"其他"块算法

**Files:**
- Modify: [CubeCleaner/Service/CubeCleanerBackend.swift](CubeCleaner/Service/CubeCleanerBackend.swift) — `TreeMapRectangle` 结构（L491 附近）与 `getValidChildren`（L848 附近）

**Interfaces:**
- Consumes: `TreeNode`（含 `item: FileSystemItem`、`children: [TreeNode]`、`totalSize: Int64`），现有 `BinaryTreeMapCalculator.binaryTreeMap`。
- Produces: `getValidChildren` 返回 `[TreeNode]`，其中可能包含一个虚拟"其他"节点（通过新增的 `TreeNode` 构造，`item.isDirectory = false`）。`TreeMapRectangle` 新增 `let isAggregated: Bool` 字段。

**说明：** Swift macOS app 项目，仓库无 XCTest target。本计划用"人工验证 + 构建通过"代替单测（测试补全记入 NEXT_STEPS P1）。因此每个任务的"写失败测试→实现→通过"流程替换为"改代码→构建通过→人工验证"。

- [ ] **Step 1: 给 `TreeMapRectangle` 加 `isAggregated` 标记**

打开 [CubeCleanerBackend.swift](CubeCleaner/Service/CubeCleanerBackend.swift)，找到 `struct TreeMapRectangle: Identifiable {`（约 L491），把字段定义改为：

```swift
struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let level: Int
    let isAggregated: Bool  // 是否为聚合的"其他"块
```

并找到 `createLeafRectangle`（约 L898）改为传入新参数：

```swift
private func createLeafRectangle(node: TreeNode, rect: CGRect, depth: Int, isAggregated: Bool = false) -> TreeMapRectangle {
    return TreeMapRectangle(
        node: node,
        rect: rect,
        color: colorSchemeManager.adjustedColor(for: node, maxSize: globalMaxSize),
        level: depth,
        isAggregated: isAggregated
    )
}
```

- [ ] **Step 2: 重写 `getValidChildren` 为聚合逻辑**

把现有 `getValidChildren`（约 L848-878）整段替换为：

```swift
/**
 * 获取有效子节点 - 聚合"其他"块策略
 *
 * 规则：
 * 1. 移除大小为0的节点
 * 2. 按大小降序排序
 * 3. 阈值 = 父目录总大小 × aggregateRatio (0.5%)
 * 4. 保留所有 >= 阈值的子项
 * 5. 剩余子项聚合为一个虚拟"其他"节点（面积守恒）
 * 6. 边界：若全部 < 阈值，不聚合，保留前 10 大，避免空图
 */
private func getValidChildren(_ children: [TreeNode]) -> [TreeNode] {
    let nonZeroChildren = children.filter { $0.totalSize > 0 }
    guard !nonZeroChildren.isEmpty else { return [] }

    // 子节点不多，直接返回
    if nonZeroChildren.count <= 5 {
        return nonZeroChildren
    }

    let sortedChildren = nonZeroChildren.sorted { $0.totalSize > $1.totalSize }
    let totalSize = sortedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
    let threshold = Int64(Double(totalSize) * minFileRatio)

    // 分离保留项与待聚合项
    var kept: [TreeNode] = []
    var aggregatedChildren: [TreeNode] = []

    for child in sortedChildren {
        if child.totalSize >= threshold {
            kept.append(child)
        } else {
            aggregatedChildren.append(child)
        }
    }

    // 边界：若全部 < 阈值（即 kept 为空），保留前 10 大，不聚合
    if kept.isEmpty {
        return Array(sortedChildren.prefix(10))
    }

    // 没有可聚合的小文件，直接返回
    if aggregatedChildren.isEmpty {
        return kept
    }

    // 构造虚拟"其他"节点
    let aggregatedSize = aggregatedChildren.reduce(Int64(0)) { $0 + $1.totalSize }
    let otherItem = FileSystemItem(
        name: "其他 (\(aggregatedChildren.count) 项)",
        path: URL(fileURLWithPath: "/__aggregated__"),
        size: aggregatedSize,
        isDirectory: false,
        creationDate: Date(timeIntervalSince1970: 0),
        modificationDate: Date(timeIntervalSince1970: 0)
    )
    let otherNode = TreeNode(item: otherItem, parent: nil)
    otherNode.markAsAggregated()

    return kept + [otherNode]
}
```

注意：`minFileRatio` 字段已存在（L607，值 0.01）。本步先用现有 `minFileRatio`，下一步统一改成 0.005。`markAsAggregated()` 在 Step 3 加。

- [ ] **Step 3: 给 `TreeNode` 加聚合标记**

找到 `class TreeNode`（约 L317），在 `@Published var isExpanded: Bool = false` 下一行加：

```swift
    /// 是否为聚合的虚拟"其他"节点
    private(set) var isAggregated: Bool = false

    /// 标记为聚合节点
    func markAsAggregated() {
        isAggregated = true
    }
```

- [ ] **Step 4: 调整 `aggregateRatio` 阈值常量**

找到 `private let minFileRatio: Double = 0.01`（约 L607），改为：

```swift
    private let minFileRatio: Double = 0.005  // 聚合阈值：小于总大小0.5%的文件归入"其他"块
```

- [ ] **Step 5: 确保"其他"节点作为叶子绘制，不参与递归**

在 `binaryTreeMap`（约 L640）的叶子创建处确认逻辑：当 `getValidChildren` 返回的节点 `children` 为空时（"其他"节点 `children` 为空），会走到 `createLeafRectangle`。需让"其他"节点用中性灰颜色。找到 `createLeafRectangle`，在构造前加颜色覆盖：

把 Step 1 的 `createLeafRectangle` 进一步改为：

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

（`node.isAggregated` 与参数 `isAggregated` 取其一即可，这里以 `node.isAggregated` 为准，参数保留为兼容。）

- [ ] **Step 6: 构建验证**

Run: `cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20`
Expected: 输出 `[SUCCESS] 构建成功！`，无编译错误。

- [ ] **Step 7: 人工验证面积守恒**

Run the app: `cd /Users/gwm/code/CubeCleaner && ./build.sh run`
扫描一个含大量小文件的目录（如 `~/Library/Caches`）。确认：
- 出现灰色"其他 (N 项)"块。
- 大矩形 + 其他块的视觉面积之和 ≈ 整个画布。
- 无大量过细矩形（小文件已被吸收进"其他"）。

- [ ] **Step 8: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add CubeCleaner/Service/CubeCleanerBackend.swift
git commit -m "feat: TreeMap 聚合小文件为'其他'块，保证面积守恒

将 getValidChildren 的丢弃逻辑改为聚合：低于阈值(0.5%)的子项
合并为虚拟'其他'节点，面积守恒，消除过细矩形。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: 双击导航进入子目录 + currentRoot

**Files:**
- Modify: [CubeCleaner/ContentView.swift](CubeCleaner/ContentView.swift) — `ContentView` 状态（L11-24）、`TreeMapCanvasView`（L309-351）、`updateLayoutOptimized`（L262）

**Interfaces:**
- Consumes: `TreeNode.parent`、`TreeNode.item.isDirectory`、`FileSystemService.rootNode`。
- Produces: `ContentView.currentRoot: TreeNode?`，布局以 `currentRoot` 为根；`TreeMapCanvasView` 新增 `onDoubleTap: (TreeMapRectangle) -> Void` 回调。

- [ ] **Step 1: 给 ContentView 加 `currentRoot` 状态**

在 [ContentView.swift](CubeCleaner/ContentView.swift) 找到状态声明区（约 L11-24），在 `@State private var selectedNode: TreeNode?` 下一行加：

```swift
    @State private var currentRoot: TreeNode?
```

- [ ] **Step 2: 扫描完成后初始化 `currentRoot`**

找到 `.onChange(of: fileSystemService.rootNode)`（约 L175），改为：

```swift
                .onChange(of: fileSystemService.rootNode) { _, newNode in
                    currentRoot = newNode
                    Task {
                        await updateLayoutOptimized(size: geometry.size)
                    }
                }
```

- [ ] **Step 3: 布局改用 `currentRoot`**

找到 `updateLayoutOptimized`（约 L262），把 `guard let rootNode = fileSystemService.rootNode,` 改为：

```swift
        guard let rootNode = currentRoot ?? fileSystemService.rootNode,
```

其余不变（`rootNode` 这个局部变量名沿用，指向 `currentRoot`）。

- [ ] **Step 4: 给 `TreeMapCanvasView` 加双击回调**

找到 `struct TreeMapCanvasView`（约 L309），把属性区改为：

```swift
struct TreeMapCanvasView: View {
    let rectangles: [TreeMapRectangle]
    let onTap: (TreeMapRectangle) -> Void
    let onLongPress: (TreeMapRectangle) -> Void
    let onDoubleTap: (TreeMapRectangle) -> Void

    @State private var hoveredRectangle: TreeMapRectangle?
```

- [ ] **Step 5: 实现双击手势**

在 `TreeMapCanvasView.body` 的 `.gesture(...)` 区（约 L323-349），在长按手势之后追加双击手势。找到 `.onHover { _ in }`（约 L350），在其**之前**插入：

```swift
        .onTapGesture(count: 2) { _ in
            // 双击由 DragGesture 的 location 无法直接拿到，改用 spatialTapGesture
        }
        .gesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    if let hitRectangle = findRectangleAt(value.location) {
                        onDoubleTap(hitRectangle)
                    }
                }
        )
```

并把单击改为 `SpatialTapGesture` 以拿到 location（替换原 `DragGesture(minimumDistance: 0)` 的 onTap 分支）。找到原 onTap 的 `.gesture(DragGesture(minimumDistance: 0).onEnded { ... onTap ... })`，替换为：

```swift
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    if let hitRectangle = findRectangleAt(value.location) {
                        onTap(hitRectangle)
                    }
                }
        )
```

注意：`SpatialTapGesture` 的 `value.location` 是相对 Canvas 的坐标，与 `findRectangleAt` 用的坐标系一致。

- [ ] **Step 6: 在 ContentView 传入双击回调并实现导航**

找到 `TreeMapCanvasView(` 调用处（约 L98-110），把整个调用改为：

```swift
                        TreeMapCanvasView(
                            rectangles: rectangles,
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
                                if rectangle.node.item.isDirectory && !rectangle.node.isAggregated {
                                    currentRoot = rectangle.node
                                    Task {
                                        await updateLayoutOptimized(size: geometry.size)
                                    }
                                }
                            }
                        )
```

（聚合的"其他"节点 `isDirectory = false`，双击无操作，条件里 `!rectangle.node.isAggregated` 是双保险。）

- [ ] **Step 7: 构建验证**

Run: `cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20`
Expected: `[SUCCESS] 构建成功！`

- [ ] **Step 8: 人工验证导航**

Run: `./build.sh run`，扫描一个有多层子目录的文件夹。确认：
- 双击一个目录矩形 → TreeMap 切换为该子目录内容，长尾文件展开为具体矩形。
- "其他"块在新根下可能变小或消失（子目录总大小更小，阈值更低）。

- [ ] **Step 9: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add CubeCleaner/ContentView.swift
git commit -m "feat: 双击进入子目录，长尾文件自然展开

引入 currentRoot 状态，双击目录矩形切换布局根。
子目录总大小更小，聚合阈值更低，小文件展开为具体矩形。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: 面包屑导航 BreadcrumbView

**Files:**
- Modify: [CubeCleaner/ContentView.swift](CubeCleaner/ContentView.swift) — 工具栏区（L28-65）新增面包屑行，文件末尾新增 `BreadcrumbView` 结构。

**Interfaces:**
- Consumes: `currentRoot`、`TreeNode.parent`、`TreeNode.item.name`。
- Produces: `BreadcrumbView` 视图，点击某段触发 `currentRoot` 切换。

- [ ] **Step 1: 新增 BreadcrumbView 结构**

在 [ContentView.swift](CubeCleaner/ContentView.swift) 文件末尾（`#Preview` 之前，约 L711）插入：

```swift
// MARK: - 面包屑导航视图
struct BreadcrumbView: View {
    let currentRoot: TreeNode?
    let onSelect: (TreeNode) -> Void

    /// 从扫描根到 currentRoot 的路径
    private var path: [TreeNode] {
        var nodes: [TreeNode] = []
        var current: TreeNode? = currentRoot
        while let node = current {
            nodes.insert(node, at: 0)
            current = node.parent
        }
        return nodes
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { onSelect(node) }) {
                        Text(node.item.name)
                            .font(.caption)
                            .foregroundColor(index == path.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
```

- [ ] **Step 2: 在 ContentView 工具栏下方插入面包屑**

找到 `Divider()`（约 L68，工具栏与主内容区之间），在其**之后**插入：

```swift
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
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
```

注意：此处 `geometry.size` 引用在 `GeometryReader` 外层不可见。需把这段面包屑**移入** `GeometryReader { geometry in` 的 `ZStack` 内（放在 ZStack 顶部，用 `VStack` 或 alignment）。更稳妥：把面包屑放在 ZStack 外、GeometryReader 内的顶部。具体做法见 Step 3。

- [ ] **Step 3: 调整面包屑位置到 GeometryReader 内以拿到 geometry**

`Divider()` 在 L68 位于 `VStack` 内但在 `GeometryReader` 之前，没有 `geometry`。改为把面包屑放进 `GeometryReader` 的 `ZStack` 里、顶部对齐。把 Step 2 插入的内容从 `Divider()` 后**移除**，改在 `GeometryReader { geometry in` 的 `ZStack {` 内最前面加：

```swift
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
```

这样面包屑浮在 Canvas 顶部，不挤压 TreeMap 空间。

- [ ] **Step 4: 构建验证**

Run: `cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20`
Expected: `[SUCCESS] 构建成功！`

- [ ] **Step 5: 人工验证面包屑**

Run: `./build.sh run`，双击进入子目录后确认：
- 顶部出现面包屑，显示完整路径（根 > 子目录 > ...）。
- 点击面包屑某段 → 切回该层级，TreeMap 重算。
- 当前层级文字为 primary 色，其余为 secondary。

- [ ] **Step 6: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add CubeCleaner/ContentView.swift
git commit -m "feat: 面包屑导航，支持逐级返回

新增 BreadcrumbView，显示从扫描根到当前根的路径，
点击任意层级快速返回。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: 悬停复活 + 删死代码

**Files:**
- Modify: [CubeCleaner/ContentView.swift](CubeCleaner/ContentView.swift) — `TreeMapCanvasView` 的 `.onHover`（L350）、`TreeMapRectangleView`（L429-556）

**Interfaces:**
- Consumes: `TreeMapRectangle.id`、`rect`、`findRectangleAt`。
- Produces: `hoveredRectangle` 实际更新，Canvas 悬停高亮生效。

- [ ] **Step 1: 复活悬停检测**

在 [ContentView.swift](CubeCleaner/ContentView.swift) 找到 `TreeMapCanvasView` 的 `.onHover { _ in }`（约 L350），替换为真正的悬停检测。由于 Canvas 不直接给鼠标坐标，用 `onContinuousHover`（macOS 14+）或回退 `SpatialTapGesture` 同源的坐标。用 `onContinuousHover`：

把 `.onHover { _ in }  // 保持悬停检测接口` 替换为：

```swift
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoveredRectangle = findRectangleAt(location)
            case .ended:
                hoveredRectangle = nil
            }
        }
```

确认 `drawRectangle` 已读取 `hoveredRectangle`（L358 `let isHovered = hoveredRectangle?.id == rectangle.id`）——已存在，无需改。

- [ ] **Step 2: 删除死代码 `TreeMapRectangleView`**

找到 `struct TreeMapRectangleView: View {`（约 L429）到其闭合 `}`（约 L556，即 `private func makeTooltipText()` 的 `}` 之后）。整段删除（该视图无人引用，ContentView 实际用 `TreeMapCanvasView`）。

确认删除后无编译错误引用 `TreeMapRectangleView`。

- [ ] **Step 3: 构建验证**

Run: `cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20`
Expected: `[SUCCESS] 构建成功！`，无 "cannot find type 'TreeMapRectangleView'" 之类错误。

- [ ] **Step 4: 人工验证悬停**

Run: `./build.sh run`，扫描一个目录。确认：
- 鼠标移到某矩形上 → 该矩形高亮（透明度 0.95）。
- 移开 → 恢复 0.8。

- [ ] **Step 5: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add CubeCleaner/ContentView.swift
git commit -m "feat: 复活 Canvas 悬停高亮，删除死代码 TreeMapRectangleView

用 onContinuousHover 更新 hoveredRectangle，悬停高亮生效。
TreeMapRectangleView 无人引用，删除以减负。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: 重写 README.md

**Files:**
- Modify: [README.md](README.md)

**Interfaces:** 无（纯文档）。

- [ ] **Step 1: 修正 Roadmap 与结构图**

打开 [README.md](README.md)。
- L1-3 标题区不变。
- 把 L27-39 的"Project Structure"图替换为实际结构：

```markdown
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

- 把 L64-94 的 Roadmap 改为反映 v0.2 实际完成度：

```markdown
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
```

- 在 "## License" 段（L100-102）后补一句状态：

```markdown
## License

本项目采用 MIT License。⚠️ 注意：仓库当前尚未包含 LICENSE 文件，待后续补齐（见 NEXT_STEPS P2）。
```

- 在 "## Getting Started" 的现状说明里，把第一句简介补一句版本状态：在 L3 末尾"manage your disk space effectively."后加一句：

```markdown
**当前状态：v0.2-beta，基础扫描与 TreeMap 可视化可用。**
```

- [ ] **Step 2: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add README.md
git commit -m "docs: README 照实记录 v0.2 现状，修正 Roadmap 与结构图

Roadmap 按实际完成度勾选，结构图反映 3 文件实际结构，
标注 LICENSE 文件待补。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: 重写 NEXT_STEPS.md

**Files:**
- Modify: [NEXT_STEPS.md](NEXT_STEPS.md)

**Interfaces:** 无（纯文档）。

- [ ] **Step 1: 整文件重写**

用以下内容**整体覆盖** [NEXT_STEPS.md](NEXT_STEPS.md)：

```markdown
# CubeCleaner 下一步开发指南

> 本文档描述 v0.2-beta 之后的开发计划，按优先级分层。
> 文档与代码现状对照见 docs/Requirements.md 与 docs/Programming-Design.md。

## 当前状态 (v0.2-beta)

- ✅ getattrlistbulk 批量文件扫描
- ✅ 二分法 TreeMap 布局 + 聚合"其他"块（面积守恒）
- ✅ Canvas 渲染 + 点击/双击/长按交互
- ✅ 双击进入子目录 + 面包屑导航
- ✅ 详情面板、悬停高亮、Finder 集成
- ⚠️ 扫描在 @MainActor 上跑同步 IO，大目录会卡 UI
- ⚠️ 整棵 TreeNode 树常驻内存，百万级文件有压力
- ❌ 无删除/Trash 功能（沙盒只读）
- ❌ 无测试
- ❌ 无 LICENSE 文件

## P0 - 正确性 & 准确性

1. **[完成] TreeMap 聚合"其他"块 + 最小可见阈值** — 小文件归入"其他"，面积守恒。
2. **[完成] 双击进入子目录 + 面包屑导航** — 长尾自然展开。
3. **扫描移出主线程** — `FileSystemService` 去掉 `@MainActor`，`BulkFileScanner.scanDirectory` 在 `Task.detached` 或独立 actor 上执行，进度通过 `@Published` 回主线程。修复 PR-003。
4. **聚合面积守恒的自动化验证** — 补单元测试断言"保留项 + 其他块面积 ≈ 父目录面积"（依赖 P1 测试基建）。

## P1 - 架构 & 可维护性

1. **拆分 CubeCleanerBackend.swift (1223 行)** →
   - `Models/`：`FileSystemItem`、`TreeNode`、`FileType`
   - `Scanning/`：`BulkFileScanner`
   - `Layout/`：`BinaryTreeMapCalculator`、`TreeMapRectangle`、`ColorSchemeManager`
   - `Services/`：`FileSystemService`
2. **拆分 ContentView.swift (715 行)** → `TreeMapCanvasView`、`DetailsPanelView`、`BreadcrumbView`、`ActionsView` 各自独立文件。
3. **补单元测试** — 覆盖：布局面积守恒、聚合阈值逻辑、`getattrlistbulk` buffer 解析、`findRectangleAt` hit-test。
4. **详情面板点击冲突修复** — 外层 `.onTapGesture` 吞掉内部按钮点击，改用背景遮罩或显式按钮命中区。

## P2 - 功能 & 生产化

1. **删除/Trash** — entitlements 加 `com.apple.security.files.user-selected.read-write`，实现移到废纸篓 + 二次确认（FR-031）。
2. **硬链接 inode 去重 + 符号链接防环** — 用 `getattrlist` 取 `ATTR_CMN_LINKID`/inode 去重；符号链接用访问过的 inode 集合防环（FR-006）。
3. **搜索过滤** — 文件名、大小范围、文件类型、修改时间（FR-028/032-035）。
4. **导出** — PNG 图片、CSV/JSON 数据（FR-048/049）。
5. **分发** — 代码签名公证、DMG 打包、补 LICENSE 文件、App Store 准备。
6. **主题与颜色方案** — 深浅色完善、多颜色方案切换（按大小/日期/扩展名，FR-012-021）。

## 版本里程碑

- **v0.2** ✅：基础 TreeMap + 聚合 + 导航 + 详情面板（当前）
- **v0.3**：扫描移出主线程、P0/P1 架构拆分与测试
- **v0.4**：删除、搜索过滤、硬链接处理
- **v0.5**：导出、主题、性能优化
- **v1.0**：生产就绪（签名、打包、App Store）

---

*更新时间：2026-06-24*
```

- [ ] **Step 2: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add NEXT_STEPS.md
git commit -m "docs: 重写 NEXT_STEPS，按 P0/P1/P2 分层，消除自相矛盾

删除旧的矛盾内容（顶部说集成完成、末尾说未集成），
改为基于 v0.2 现状的分层计划。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: 重写 docs/Requirements.md 加状态标记

**Files:**
- Modify: [docs/Requirements.md](docs/Requirements.md)

**Interfaces:** 无（纯文档）。

- [ ] **Step 1: 在文件顶部加状态说明**

打开 [docs/Requirements.md](docs/Requirements.md)。在 "## 1. Project Overview" 之前（L1 标题之后）插入：

```markdown
> **实现状态对照（截至 v0.2-beta）**
> 每条需求后附标记：✅ 完成 / ⚠️ 部分完成 / ❌ 未实现。
> 关键差距：FR-006 硬链接(❌)、FR-031 删除(❌)、PR-003 后台扫描不阻塞UI(⚠️)、PR-005 内存<500MB(⚠️)。

```

- [ ] **Step 2: 给 2.1.1 Disk Scanning 各条加状态**

把 L18-25 的 FR-001 到 FR-006 改为：

```markdown
#### 2.1.1 Disk Scanning
- **FR-001**: Scan entire volumes or selected directories ✅
- **FR-002**: Recursively traverse directory structures ✅
- **FR-003**: Calculate file and folder sizes accurately ✅
- **FR-004**: Handle system files and permissions appropriately ⚠️ (有权限拒绝回退，但无统一错误处理)
- **FR-005**: Support scanning of Time Machine backups ❌
- **FR-006**: Handle hard-linked files and folders correctly ❌ (硬链接会重复计算)
```

- [ ] **Step 3: 给 Visualization 各条加状态**

把 L26-31 的 FR-007 到 FR-011 改为：

```markdown
#### 2.1.2 Visualization (Tree Map)
- **FR-007**: Display files as rectangles with area proportional to file size ✅
- **FR-008**: Group files within the same folder together ✅
- **FR-009**: Provide smooth zooming and panning capabilities ❌
- **FR-010**: Support animated transitions when navigating ⚠️ (有 layout 动画，无导航过渡)
- **FR-011**: Implement responsive drawing optimized for performance ✅ (Canvas + resize 防抖)
```

- [ ] **Step 4: 给 Color Coding 各条加状态**

把 L33-42 的 FR-012 到 FR-022，整体替换为：

```markdown
#### 2.1.3 Color Coding System
- **FR-012**: Color files by name patterns ❌
- **FR-013**: Color files by extension ❌
- **FR-014**: Color files by file type ✅
- **FR-015**: Color files by parent folder ❌
- **FR-016**: Color files by top-level folder ❌
- **FR-017**: Color files by hierarchy level ❌
- **FR-018**: Color files by creation time ❌
- **FR-019**: Color files by modification time ❌
- **FR-020**: Color files by last access time ❌
- **FR-021**: Provide multiple color palette options ❌
- **FR-022**: Allow custom color mapping configuration ❌
```

- [ ] **Step 5: 给 Navigation、Filtering、Multiple Views、Persistence 各条加状态**

把 L44-49 的 FR-023~031 改为：

```markdown
#### 2.1.4 Navigation and Interaction
- **FR-023**: Navigate using mouse interactions (click, scroll, drag) ⚠️ (点击/双击/长按有，无滚轮缩放拖动)
- **FR-024**: Navigate using keyboard shortcuts ❌
- **FR-025**: Provide breadcrumb navigation ✅
- **FR-026**: Support traversing up and down folder hierarchy ✅ (双击进入 + 面包屑返回)
- **FR-027**: Allow selection of files and folders in the view ✅
- **FR-028**: Implement search functionality by file name ❌
- **FR-029**: Support Quick Look preview integration ❌
- **FR-030**: Reveal files/folders in Finder ✅
- **FR-031**: Delete files/folders directly from the view ❌ (沙盒只读)
```

把 L52-60 的 FR-032~040 整体替换为：

```markdown
#### 2.1.5 Filtering System
- **FR-032**: Filter by file name patterns ❌
- **FR-033**: Filter by file path ❌
- **FR-034**: Filter by file size ranges ❌
- **FR-035**: Filter by file type ❌
- **FR-036**: Filter by hard-link status ❌
- **FR-037**: Filter by package status ❌
- **FR-038**: Save and manage filter presets ❌
- **FR-039**: Apply filters to mask files in view ❌
- **FR-040**: Apply filters to exclude files during scanning ❌
```

把 L62-66 的 FR-041~045 整体替换为：

```markdown
#### 2.1.6 Multiple Views Support
- **FR-041**: Support multiple simultaneous views ❌
- **FR-042**: Refresh existing views ✅ (重新扫描)
- **FR-043**: Rescan directories to compare before/after cleanup ⚠️ (可重扫，无对比视图)
- **FR-044**: Twin/duplicate views for different display options ❌
- **FR-045**: Synchronize navigation between related views ❌
```

把 L68-72 的 FR-046~050 整体替换为：

```markdown
#### 2.1.7 Data Persistence
- **FR-046**: Save scan results to disk ❌
- **FR-047**: Load previously saved scan results ❌
- **FR-048**: Export views as images (PNG, JPEG) ❌
- **FR-049**: Export data as text/CSV format ❌
- **FR-050**: Maintain user preferences across sessions ❌
```

- [ ] **Step 6: 给 Performance Requirements 加状态**

把 L106-118 的 PR-001~010 改为：

```markdown
#### 2.3.1 Scanning Performance
- **PR-001**: Scan 100GB of data within 30 seconds (SSD) ⚠️ (getattrlistbulk 批量扫描快，但未基准测试)
- **PR-002**: Support scanning drives with millions of files ⚠️ (能扫但内存压力大)
- **PR-003**: Background scanning without blocking UI ❌ (当前 @MainActor 同步 IO，会卡 UI)
- **PR-004**: Cancellable scanning operations ✅
- **PR-005**: Memory usage under 500MB for large datasets ❌ (整棵 TreeNode 树常驻内存)

#### 2.3.2 Rendering Performance
- **PR-006**: Smooth 60fps scrolling and zooming ⚠️ (Canvas 渲染流畅，但无缩放)
- **PR-007**: Render initial view within 2 seconds after scan ✅
- **PR-008**: Support views with 100,000+ visible rectangles ⚠️ (聚合后矩形数大减，未压测上限)
- **PR-009**: Efficient redraw on window resize ✅ (0.3s 防抖)
- **PR-010**: Background rendering threads ✅ (Task.detached 算布局)
```

- [ ] **Step 7: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add docs/Requirements.md
git commit -m "docs: Requirements 逐条标注 v0.2 实现状态

每条 FR/PR 后附 ✅/⚠️/❌ 标记，顶部加关键差距说明。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: 重写 docs/Interface-Design.md 改为实际布局

**Files:**
- Modify: [docs/Interface-Design.md](docs/Interface-Design.md)

**Interfaces:** 无（纯文档）。

- [ ] **Step 1: 替换窗口结构图为实际布局**

打开 [docs/Interface-Design.md](docs/Interface-Design.md)。把 L43-67 的 "#### 3.1.1 Window Structure" 整段替换为：

```markdown
#### 3.1.1 Window Structure (v0.2 实际布局)
```
┌─────────────────────────────────────────────────────────────┐
│ [选择文件夹] [取消扫描]              已选择:xxx 文件数:xxx │ 工具栏
├─────────────────────────────────────────────────────────────┤
│ 根 > 子目录 > ...                                (面包屑)   │
├─────────────────────────────────────────────────────────────┤
│ ┌──────── TreeMap Canvas ──────────────┐ ┌─详情浮层──────┐ │
│ │  ┌─────┐ ┌──┐ ┌─────────┐            │ │ 文件详情      │ │
│ │  │     │ │  │ │         │            │ │ 大小/类型/路径│ │
│ │  └─────┘ └──┘ └─────────┘            │ │ 子项目列表    │ │
│ │  ┌──────────────────────┐ [其他 N 项] │ │ [Finder显示] │ │
│ │  │                      │             │ └───────────────┘ │
│ │  └──────────────────────┘             │                   │
│ └────────────────────────────────────────┘                   │
├─────────────────────────────────────────────────────────────┤
│ 总大小: xxx                          文件数: xxx            │ 状态栏
└─────────────────────────────────────────────────────────────┘
```
- 单 Canvas 居中，详情面板为浮层（点击矩形弹出）。
- 面包屑浮于 Canvas 顶部。
- 无 Sidebar / Inspector 双侧栏（计划中，见 NEXT_STEPS）。
```

- [ ] **Step 2: 修正 3.1.2 Responsive Layout**

把 L69-74 的 "#### 3.1.2 Responsive Layout" 替换为：

```markdown
#### 3.1.2 Responsive Layout
- **Minimum Width**: 由 SwiftUI 默认窗口约束
- **详情浮层**: maxWidth 500，点击空白或 × 关闭
- **TreeMap Canvas**: 占据主内容区，resize 时 0.3s 防抖重算
- **面包屑**: 水平滚动，超长不换行
```

- [ ] **Step 3: 修正交互元素为实际已实现项**

把 L223-230 的 "#### 3.5.3 Interactive Elements" 替换为：

```markdown
#### 3.5.3 Interactive Elements (v0.2 已实现)
- **单击**: 选中文件/文件夹，弹出详情面板
- **双击**: 进入子目录（切换布局根）
- **长按**: 在 Finder 中显示
- **悬停**: 矩形高亮（透明度变化）

#### 计划中的交互
- 右键上下文菜单
- 滚轮/双指缩放平移
- Cmd+click 多选
- Quick Look 预览 (Space)
```

- [ ] **Step 4: 把未实现的菜单/快捷键移到"计划中"小节**

找到 "### 3.2 Menu Bar Structure"（L76），在其**之前**插入说明，并把整段菜单结构（L76-127）用引用块标注为计划中。即在 L76 之前加：

```markdown
### 3.2 Menu Bar Structure (计划中)

> v0.2 尚未实现菜单栏与快捷键系统，以下为目标设计：
```

并把 L129-145 的 "### 3.3 Toolbar Design" 替换为实际工具栏：

```markdown
### 3.3 Toolbar Design (v0.2 实际)
```
[选择文件夹]  [取消扫描(扫描中显示)]        状态信息(右对齐)
```
| 控件 | 行为 |
|------|------|
| 选择文件夹 | 弹出文件选择器，选目录后开始扫描 |
| 取消扫描 | 仅扫描中显示，取消当前 Task |
| 状态信息 | 显示已选目录名、文件数、总大小 |
```

- [ ] **Step 5: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add docs/Interface-Design.md
git commit -m "docs: Interface-Design 改为 v0.2 实际布局

窗口结构图反映单 Canvas + 浮层 + 面包屑实际布局，
菜单/快捷键/侧栏标注为计划中，交互只列已实现项。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 9: 重写 docs/Programming-Design.md 照实描述架构

**Files:**
- Modify: [docs/Programming-Design.md](docs/Programming-Design.md)

**Interfaces:** 无（纯文档，改动最大）。

- [ ] **Step 1: 替换架构概览与目录结构**

打开 [docs/Programming-Design.md](docs/Programming-Design.md)。把 L1-97（从 `## 1. Architecture Overview` 到 `## 3. Core Models` 之前，即整个第 1、2 节）替换为：

```markdown
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
- **单文件后端**：`CubeCleanerBackend.swift` 含扫描/模型/颜色/布局/服务，1223 行，计划拆分（见 NEXT_STEPS P1）。
- **Canvas 渲染**：所有矩形一次性绘制，规避 SwiftUI 视图层级性能问题，自做 hit-test。
- **批量扫描**：`getattrlistbulk` 一次取多个文件属性，`FileManager` 回退。
- **resize 防抖**：拖动窗口时清空矩形，停手 0.3s 后重算。

## 2. Project Structure (实际)

```
CubeCleaner/
├── CubeCleanerApp.swift            # App 入口 (17 行)
├── ContentView.swift               # 主视图 + Canvas + 浮层 (715 行)
├── CubeCleaner.entitlements        # 沙盒权限 (user-selected.read-only)
├── Assets.xcassets/                # App 图标 / 强调色
└── Service/
    └── CubeCleanerBackend.swift     # 扫描/模型/颜色/布局/服务 (1223 行)
```

### 2.1 CubeCleanerBackend.swift 内部分块

该单文件按 MARK 分 5 块（见文件头注释）：

| 块 | 内容 | 行数(约) |
|----|------|----------|
| 扫描模块 | `BulkFileAttributes`、`BulkFileScanner` (getattrlistbulk) | 1-259 |
| 数据模型 | `FileSystemItem`、`TreeNode`、`FileType` | 261-416 |
| 可视化 | `ColorSchemeManager`、`TreeMapRectangle`、`BinaryTreeMapCalculator` | 418-906 |
| 文件系统服务 | `FileSystemService` (@MainActor) | 908-1186 |
| 工具 | `FileSystemError`、`Array.chunked` | 1188-1223 |
```

- [ ] **Step 2: 替换数据模型章节为真实代码**

把 L99-205 的 "## 3. Core Models" 整节（含 3.1 FileSystemItem、3.2 TreeNode 的伪代码）替换为：

```markdown
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
    // ... displayName/canShowSize/formattedSize/isImportant 等计算属性
}
```
```

- [ ] **Step 3: 替换布局算法章节**

把 L679-828 的 "## 6. Layout Algorithm" 整节（含虚构的 `TreeMapLayoutCalculator`/squarify 伪代码）替换为：

```markdown
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
```

- [ ] **Step 4: 替换 ViewModel/Service 章节**

把 L243-677 的 "## 4. ViewModels" 与 "## 5. Services" 整节替换为：

```markdown
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
```

- [ ] **Step 5: 替换视图实现章节**

把 L831-951 的 "## 7. Key Views Implementation" 替换为：

```markdown
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
```

- [ ] **Step 6: 替换测试与性能章节**

把 L953-1108 的 "## 8. Testing Strategy" 与 "## 9. Performance Optimization" 替换为：

```markdown
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
```

- [ ] **Step 7: 替换错误处理章节**

把 L1074-1108 的 "## 10. Error Handling" 替换为：

```markdown
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
```

- [ ] **Step 8: 更新文档末尾说明**

把 L1108 的 "This comprehensive programming design documentation..." 替换为：

```markdown
本文档照实描述 v0.2 代码现状。目标架构与待办见 [NEXT_STEPS.md](../NEXT_STEPS.md)。
```

- [ ] **Step 9: Commit**

```bash
cd /Users/gwm/code/CubeCleaner
git add docs/Programming-Design.md
git commit -m "docs: Programming-Design 照实描述 v0.2 架构

删除虚构的 MVVM + 多文件目录树，改为真实 3 文件结构与
真实代码片段，标注已知问题与待优化项。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 10: 全量构建验证 + 最终验证

**Files:** 无（验证）。

- [ ] **Step 1: 全量构建**

Run: `cd /Users/gwm/code/CubeCleaner && ./build.sh clean && ./build.sh build 2>&1 | tail -25`
Expected: `[SUCCESS] 构建成功！`

- [ ] **Step 2: 端到端人工验证**

Run: `./build.sh run`，扫描 `~/Library/Caches` 或 `~/Downloads`。逐项确认：
- 扫描完成，TreeMap 显示，含灰色"其他 (N 项)"块。
- 无大量过细矩形。
- 双击目录进入，长尾展开。
- 面包屑显示路径，可逐级点回。
- 悬停矩形高亮。
- 单击弹详情，长按 Finder 显示。

- [ ] **Step 3: 文档一致性抽查**

确认文档描述与代码一致：
- `docs/Programming-Design.md` 提到的文件/类/方法在代码中存在。
- `docs/Requirements.md` 的 ✅ 项确实能用。
- `README.md` 结构图与实际目录一致。
- `NEXT_STEPS.md` 无自相矛盾。

- [ ] **Step 4: 检查 git 状态干净**

Run: `git status`
Expected: `nothing to commit, working tree clean`（所有改动已分任务提交）。

- [ ] **Step 5: 最终提交（如有遗漏的验证记录）**

若 Step 1-4 全通过且工作区干净，无需额外提交。否则补提交。

---

## 完成标准

- [ ] `./build.sh build` 通过。
- [ ] TreeMap 无过细矩形，含"其他"块，面积守恒。
- [ ] 双击进子目录 + 面包屑返回可用。
- [ ] 悬停高亮生效。
- [ ] 死代码 `TreeMapRectangleView` 已删。
- [ ] 5 个文档全部照实记录 v0.2 现状，无矛盾。
- [ ] `NEXT_STEPS.md` 按 P0/P1/P2 重排。
- [ ] 每个 Task 独立提交，工作区干净。
