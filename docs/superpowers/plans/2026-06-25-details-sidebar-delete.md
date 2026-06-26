# CubeCleaner v0.3.1 详情侧栏化 + 删除 + 钻取统计刷新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把选中详情从中间浮层挪进右侧侧栏分页切换、钻取后顶部统计随 currentRoot 刷新、新增"移到废纸篓"删除按钮（二次确认 + 重扫）。

**Architecture:** 纯 UI/交互层改造，不重写布局算法。数据层加子树统计纯函数与 trashAndRescan；视图层把 `DetailsPanelView` 改成侧栏页、侧栏加 Picker 分页、`StatsBarView` 改读子树状态、`ActionsView` 加删除按钮 + confirmationDialog；entitlements 改 read-write 以允许 trashItem。

**Tech Stack:** Swift 5.0, SwiftUI, macOS 15.5 deployment target, `FileManager.trashItem`, `confirmationDialog`.

**Repo note:** 仓库无 XCTest target。本计划以 `./build.sh build` 通过为每任务验收门槛（替代单元测试）。所有 `git` 命令须 `git -C /Users/gwm/code/CubeCleaner`（工作目录是 `/Users/gwm`，不在仓库内）。

## Global Constraints

- 部署目标 macOS 15.5、Swift 5.0（与现有 Xcode 工程一致）。
- 不重写 `BinaryTreeMapCalculator` 布局算法。
- 删除 = 移到废纸篓（`FileManager.default.trashItem`），非永久删除。
- 删除后重扫扫描根（`fileSystemService.scanDirectory(at: scanRootURL)`）。
- entitlements 必须由 `com.apple.security.files.user-selected.read-only` 改为 `read-write`，否则沙盒拒 trashItem。
- 提交信息中文，结尾含 `Co-Authored-By: Claude <noreply@anthropic.com>`。
- 所有改动在 `ljj/rebuild` 分支上提交。

---

## File Structure

- `CubeCleaner/CubeCleaner.entitlements` — read-only → read-write。
- `CubeCleaner/Service/CubeCleanerBackend.swift` — 加 `fileCountInSubtree`/`folderCountInSubtree` 纯函数 + `FileSystemService.trashAndRescan`。
- `CubeCleaner/ContentView.swift` — 侧栏分页、DetailsSidebarView、删除按钮+确认、子树统计刷新、StatsBarView 改读子树、fileImporter 记 scanRootURL、删浮层。

任务依赖：Task 1（entitlements）→ Task 2（子树统计纯函数）→ Task 3（trashAndRescan）→ Task 4（DetailsSidebarView 改名+去浮层）→ Task 5（侧栏分页 SidebarTabView）→ Task 6（ActionsView 删除按钮+确认）→ Task 7（ContentView 组装：删浮层、onTap 跳详情、子树统计刷新、StatsBarView 改读、fileImporter 记 scanRootURL）→ Task 8（最终构建 + 文档订正）。

---

### Task 1: entitlements 改 read-write

**Files:**
- Modify: `CubeCleaner/CubeCleaner.entitlements`

**Interfaces:**
- Produces: read-write 沙盒权限，供 Task 3 `trashItem` 使用。

- [ ] **Step 1: 改 entitlements 键名**

把 `CubeCleaner/CubeCleaner.entitlements` 内：

```xml
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
```

改为：

```xml
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/CubeCleaner.entitlements
git -C /Users/gwm/code/CubeCleaner commit -m "feat: entitlements 改 read-write 以支持移到废纸篓

trashItem 需要写权限，user-selected 由 read-only 改为 read-write。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 子树统计纯函数

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`ColorSchemeManager` 类内，`typeBreakdown` 方法之后）

**Interfaces:**
- Consumes: `TreeNode`（`item.isDirectory`、`children`）。
- Produces: `func fileCountInSubtree(_ node: TreeNode) -> Int`、`func folderCountInSubtree(_ node: TreeNode) -> Int`，供 Task 7 刷新子树统计。

- [ ] **Step 1: 在 ColorSchemeManager 内 typeBreakdown 方法之后插入两个纯函数**

在 `typeBreakdown(for:)` 方法闭合 `}` 之后、类闭合 `}` 之前插入：

```swift
    /// 统计 node 子树的叶子文件数（非目录）
    func fileCountInSubtree(_ node: TreeNode) -> Int {
        if node.item.isDirectory {
            return node.children.reduce(0) { $0 + fileCountInSubtree($1) }
        } else {
            return 1
        }
    }

    /// 统计 node 子树的目录数（含 node 自身若为目录）
    func folderCountInSubtree(_ node: TreeNode) -> Int {
        let selfCount = node.item.isDirectory ? 1 : 0
        return selfCount + node.children.reduce(0) { $0 + folderCountInSubtree($1) }
    }
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ColorSchemeManager 加子树统计纯函数

fileCountInSubtree/folderCountInSubtree 递归统计子树文件与目录数，
供顶部统计条随钻取根刷新。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: FileSystemService.trashAndRescan

**Files:**
- Modify: `CubeCleaner/Service/CubeCleanerBackend.swift`（`FileSystemService` 类内，`scanDirectory(at:)` 附近）

**Interfaces:**
- Consumes: `FileManager.default.trashItem`、`scanDirectory(at:)`（现有）、Task 1 的 read-write entitlement。
- Produces: `func trashAndRescan(deleteURL: URL, scanRootURL: URL?)`，供 Task 6 ActionsView 删除按钮调用。

- [ ] **Step 1: 在 FileSystemService 内 scanDirectory 方法之后插入 trashAndRescan**

先 grep 定位 `func scanDirectory(at url: URL)` 找到该方法结束位置：
```bash
grep -n "func scanDirectory" CubeCleaner/Service/CubeCleanerBackend.swift
```
在该方法闭合 `}` 之后插入：

```swift
    /// 移到废纸篓后重扫扫描根，使 TreeMap/统计/图例同步。
    /// trashItem 需 read-write entitlement。
    func trashAndRescan(deleteURL: URL, scanRootURL: URL?) {
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: deleteURL, resultingItemURL: &resultingURL)
            if let scanRoot = scanRootURL {
                scanDirectory(at: scanRoot)
            }
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 2: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/Service/CubeCleanerBackend.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: FileSystemService 加 trashAndRescan

trashItem 移到废纸篓后重扫扫描根，错误写入 errorMessage。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: DetailsPanelView 改名 DetailsSidebarView 并去浮层样式

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`DetailsPanelView` 结构体，约 520-595 行）

**Interfaces:**
- Consumes: `selectedNode: TreeNode?`（binding 或 let，见下）、`fileSystemService`。
- Produces: `struct DetailsSidebarView: View`，去浮层样式 + ScrollView + 空态占位，供 Task 5 侧栏分页引用。

- [ ] **Step 1: 把 DetailsPanelView 改名为 DetailsSidebarView 并重构 body**

把现有 `struct DetailsPanelView: View` 整段（约 520-595 行）替换为：

```swift
// MARK: - 详情侧栏视图（原中间浮层，改为侧栏页）
struct DetailsSidebarView: View {
    @Binding var selectedNode: TreeNode?
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onRequestDelete: (TreeNode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let selectedNode = selectedNode {
                    Text(selectedNode.item.name)
                        .font(.title3)
                        .fontWeight(.medium)

                    Text(
                        "大小: \(ByteCountFormatter.string(fromByteCount: selectedNode.totalSize, countStyle: .file))"
                    )
                    .font(.body)

                    Text("类型: \(selectedNode.item.isDirectory ? "文件夹" : "文件")")
                        .font(.body)

                    Text("路径:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(selectedNode.item.path.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if selectedNode.item.isDirectory && !selectedNode.children.isEmpty {
                        ChildrenListView(
                            selectedNode: selectedNode,
                            onSelectChild: { child in
                                self.selectedNode = child
                            })
                    }

                    ActionsView(
                        selectedNode: selectedNode,
                        fileSystemService: fileSystemService,
                        scanRootURL: scanRootURL,
                        onDelete: { onRequestDelete(selectedNode) }
                    )
                } else {
                    Text("点击矩形查看详情")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
```

> 注：`DetailsSidebarView` 不再有 `showingDetails` binding（浮层开关移除）；新增 `scanRootURL` 与 `onRequestDelete` 供删除流程。`ActionsView` 的签名在 Task 6 改（去 `onClose`，加 `scanRootURL` + `onDelete`），本任务先按新签名引用，Task 6 会同步改 ActionsView 定义；故本任务末尾构建会因 ActionsView 签名不匹配而失败——属预期，Task 6 修复。若希望本任务独立可构建，可暂保留旧 ActionsView 签名，但为减少反复，本计划选择在 Task 6 统一改 ActionsView。

- [ ] **Step 2: 构建验证（预期 ActionsView 签名错误）**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20
```
Expected: 编译因 `ActionsView` 调用与定义签名不符而失败（缺 `scanRootURL`/`onDelete`、多 `onClose`）。**确认错误仅限 ActionsView 签名相关，DetailsSidebarView 本身无语法/类型错误。** 继续到 Task 6。

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: DetailsPanelView 改名 DetailsSidebarView 去浮层样式

去 shadow/cornerRadius/maxWidth/onTapGesture 关闭，改 ScrollView
全高，加空态占位，签名加 scanRootURL/onRequestDelete。ActionsView
签名将在后续任务同步。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 侧栏分页 SidebarTabView

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`LegendSidebarView` 之前插入 `SidebarTab` 枚举 + `SidebarTabView`）

**Interfaces:**
- Consumes: `LegendSidebarView`（现有）、`DetailsSidebarView`（Task 4 产出）、`selectedNode`、`fileSystemService`、`scanRootURL`、`highlightedFileType`、`typeBreakdown`、`onToggleHighlight`、`onRequestDelete`。
- Produces: `enum SidebarTab`、`struct SidebarTabView: View`（Picker segmented + 分页），供 Task 7 替换原侧栏。

- [ ] **Step 1: 在 LegendSidebarView 定义之前插入 SidebarTab 枚举与 SidebarTabView**

找到 `struct LegendSidebarView: View {` 这一行，在其之前插入：

```swift
// MARK: - 侧栏分页（图例 / 详情）
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

- [ ] **Step 2: 构建验证（预期 ActionsView 签名错误延续）**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20
```
Expected: 仍因 Task 4 引入的 ActionsView 签名不匹配而失败。SidebarTabView/SidebarTab 本身应无新错误。确认无新语法/类型错误。继续到 Task 6。

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: 新增侧栏分页 SidebarTabView

Picker segmented 切换图例/详情页，详情页引用 DetailsSidebarView。
供 ContentView 组装时替换原纯图例侧栏。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: ActionsView 加删除按钮 + 二次确认

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（`ActionsView` 结构体，约 647-671 行）

**Interfaces:**
- Consumes: `fileSystemService.trashAndRescan`（Task 3）、`scanRootURL`。
- Produces: 新 `ActionsView` 签名（去 `onClose`，加 `scanRootURL` + `onDelete`）+ 删除按钮 + `.confirmationDialog`，修复 Task 4/5 的签名错误。

- [ ] **Step 1: 替换 ActionsView 整段**

把现有 `struct ActionsView: View` 整段（约 647-671 行）替换为：

```swift
// MARK: - 操作按钮视图
struct ActionsView: View {
    let selectedNode: TreeNode
    let fileSystemService: FileSystemService
    let scanRootURL: URL?
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button("在Finder中显示") {
                NSWorkspace.shared.selectFile(
                    selectedNode.item.path.path,
                    inFileViewerRootedAtPath: ""
                )
            }
            .buttonStyle(.borderedProminent)

            Button {
                onDelete()
            } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if selectedNode.item.isDirectory {
                Button("重新扫描此文件夹") {
                    fileSystemService.scanDirectory(at: selectedNode.item.path)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
```

> 注：删除的二次确认 `.confirmationDialog` 不放 ActionsView（ActionsView 不持有 `@State` 确认开关），而放 ContentView（Task 7），由 `onRequestDelete` 回调触发 ContentView 的 `showingDeleteConfirm`。ActionsView 只负责点删除按钮时调 `onDelete()`。

- [ ] **Step 2: 构建验证（预期 DetailsSidebarView/SidebarTabView 调用点仍可能报错，因 ContentView 尚未传 onDelete/onRequestDelete）**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -20
```
Expected: ActionsView 定义已修复，但 ContentView 内若有对旧 ActionsView 的调用（旧调用传 `onClose`）会报错。本任务不改 ContentView 调用点（Task 7 改）。**确认错误仅限 ContentView 对 ActionsView 的调用点，ActionsView 本身无错误。** 继续到 Task 7。

- [ ] **Step 3: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ActionsView 加移到废纸篓按钮

签名去 onClose 加 scanRootURL/onDelete，新增 trash 图标红色按钮，
点击触发 onDelete 回调(由 ContentView 弹二次确认)。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: ContentView 组装 — 删浮层、侧栏分页、子树统计刷新、删除确认

**Files:**
- Modify: `CubeCleaner/ContentView.swift`（ContentView 状态区、Canvas onTap、侧栏块、StatsBarView 调用点、updateLayoutOptimized、fileImporter、删除浮层块）

**Interfaces:**
- Consumes: Task 1-6 全部产出。
- Produces: 完整 v0.3.1 页面。

- [ ] **Step 1: 加新状态，删 showingDetails**

在 ContentView 的 `@State` 区（约 13-24 行）：
- 删除 `@State private var showingDetails = false`
- 在 `typeBreakdown` 那行之后加：

```swift
    // v0.3.1: 侧栏分页 + 删除 + 钻取统计刷新
    @State private var sidebarTab: SidebarTab = .legend
    @State private var scanRootURL: URL?
    @State private var showingDeleteConfirm = false
    @State private var subtreeTotalSize: Int64 = 0
    @State private var subtreeFileCount: Int = 0
    @State private var subtreeFolderCount: Int = 0
```

- [ ] **Step 2: updateLayoutOptimized 末尾刷新子树统计**

在 `updateLayoutOptimized` 的 `withAnimation { ... typeBreakdown = ... }` 块内（约 352-356 行），把：

```swift
            withAnimation(.easeOut(duration: 0.25)) {
                rectangles = newRectangles
                isLayouting = false
                typeBreakdown = ColorSchemeManager.shared.typeBreakdown(for: rootNode)
            }
```

改为：

```swift
            withAnimation(.easeOut(duration: 0.25)) {
                rectangles = newRectangles
                isLayouting = false
                typeBreakdown = ColorSchemeManager.shared.typeBreakdown(for: rootNode)
                subtreeTotalSize = rootNode.totalSize
                subtreeFileCount = ColorSchemeManager.shared.fileCountInSubtree(rootNode)
                subtreeFolderCount = ColorSchemeManager.shared.folderCountInSubtree(rootNode)
            }
```

- [ ] **Step 3: StatsBarView 调用点改读子树统计**

把统计条区（约 76-81 行）：

```swift
                StatsBarView(
                    totalSize: fileSystemService.totalSize,
                    fileCount: fileSystemService.filesScanned,
                    folderCount: fileSystemService.folderCount,
                    isScanning: fileSystemService.isScanning
                )
```

改为：

```swift
                StatsBarView(
                    totalSize: subtreeTotalSize,
                    fileCount: subtreeFileCount,
                    folderCount: subtreeFolderCount,
                    isScanning: fileSystemService.isScanning
                )
```

> 扫描中态：子树统计还是 0（updateLayoutOptimized 未跑），但 `isScanning` 为 true。可在扫描中态保留显示全局值，但为简化首版，扫描中显示子树值（0）即可——StatsBarView 已有 isScanning 参数，后续可加扫描中态显示。验收只看构建通过与根目录显示正确。

- [ ] **Step 4: Canvas onTap 改为跳详情页（去 showingDetails）**

把 Canvas `onTap` 闭包（约 143-146 行）：

```swift
                            onTap: { rectangle in
                                selectedNode = rectangle.node
                                showingDetails = true
                            },
```

改为：

```swift
                            onTap: { rectangle in
                                selectedNode = rectangle.node
                                sidebarTab = .details
                            },
```

- [ ] **Step 5: 删除中间浮层块**

把 ZStack 内的浮层块（约 220-227 行）整段删除：

```swift
                    // 详情面板（浮于 Canvas 之上的覆盖层）
                    if showingDetails {
                        DetailsPanelView(
                            selectedNode: $selectedNode,
                            showingDetails: $showingDetails,
                            fileSystemService: fileSystemService
                        )
                    }
```

- [ ] **Step 6: 侧栏改为 SidebarTabView**

把 HStack 内的侧栏块（约 230-239 行）：

```swift
                    // 图例侧栏
                    if showLegend {
                        LegendSidebarView(
                            entries: typeBreakdown,
                            highlightedFileType: highlightedFileType,
                            onToggleHighlight: { type in
                                highlightedFileType = (highlightedFileType == type) ? nil : type
                            }
                        )
                    }
```

改为：

```swift
                    // 侧栏（图例/详情分页）
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

- [ ] **Step 7: 加删除二次确认 confirmationDialog**

在 ContentView 的根 `VStack` 末尾（`.fileImporter` 之前，约 277 行 `}` 之后、`.fileImporter` 之前），加 `.confirmationDialog`：

找到：
```swift
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
        }
        .fileImporter(
```

在 `.background(Color(.controlBackgroundColor))` 闭合的 `}` 之后、`.fileImporter(` 之前插入：

```swift
        .confirmationDialog(
            "移到废纸篓",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                if let node = selectedNode {
                    fileSystemService.trashAndRescan(
                        deleteURL: node.item.path,
                        scanRootURL: scanRootURL
                    )
                    selectedNode = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let node = selectedNode {
                Text("将把「\(node.item.name)」（\(ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file))）移到废纸篓，可在废纸篓中恢复。确定继续？")
            } else {
                Text("将把选中项移到废纸篓，可在废纸篓中恢复。确定继续？")
            }
        }
```

- [ ] **Step 8: fileImporter 记录 scanRootURL**

把 `fileImporter` 的 success 分支（约 284-288 行）：

```swift
            case .success(let urls):
                if let url = urls.first {
                    selectedPath = url
                    fileSystemService.scanDirectory(at: url)
                }
```

改为：

```swift
            case .success(let urls):
                if let url = urls.first {
                    selectedPath = url
                    scanRootURL = url
                    fileSystemService.scanDirectory(at: url)
                }
```

- [ ] **Step 9: 构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

若报错，常见点：
- `DetailsSidebarView`/`ActionsView`/`SidebarTabView` 的参数标签或数量不符——回查 Task 4/5/6 的签名。
- `confirmationDialog` 作用域——确保挂在 ContentView 根视图上。

迭代直到构建通过。

- [ ] **Step 10: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add CubeCleaner/ContentView.swift
git -C /Users/gwm/code/CubeCleaner commit -m "feat: ContentView 组装 v0.3.1 详情侧栏+删除+钻取刷新

侧栏改 SidebarTabView 分页(图例/详情)，删中间浮层，onTap 跳详情页，
updateLayoutOptimized 刷新子树统计，StatsBarView 改读子树值，
fileImporter 记 scanRootURL，加删除二次确认 confirmationDialog。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: 文档订正与最终构建

**Files:**
- Modify: `README.md`（状态行 v0.3→v0.3.1、Features 补详情侧栏/删除/钻取刷新）
- Modify: `docs/Interface-Design.md`（3.5.3 交互补删除/侧栏分页、3.1.1 说明行补分页侧栏）

**Interfaces:** 无。

- [ ] **Step 1: README.md 状态行与 Features 更新**

把 `README.md` 第 5 行：

```
**当前状态：v0.3-beta，顶部统计条、类型占比图例、高饱和配色与返回导航可用。**
```

改为：

```
**当前状态：v0.3.1-beta，详情侧栏分页、移到废纸篓删除、钻取统计随根刷新可用。**
```

在 `## Features (v0.3)` 标题改为 `## Features (v0.3.1)`，并在 Features 列表追加 3 条（保留现有条目）：

```
- 🗂️ **详情侧栏分页**: 选中矩形详情挪进右侧侧栏，图例/详情分页切换，常驻可滚
- 🗑️ **移到废纸篓**: 详情页垃圾桶按钮 + 二次确认，删除后自动重扫
- 🔄 **钻取统计刷新**: 进入子目录/聚合块后顶部统计随钻取根刷新
```

- [ ] **Step 2: Interface-Design.md 交互更新**

在 `docs/Interface-Design.md` 的 3.5.3 交互列表追加：

```
- **点击图例类型**: 高亮 TreeMap 中该类型矩形，其它降至 20% 透明度；再点取消（v0.3）
- **详情侧栏分页**: 选中矩形后右侧侧栏自动跳详情页，图例/详情分页切换（v0.3.1）
- **移到废纸篓**: 详情页垃圾桶按钮，二次确认后移废纸篓并重扫（v0.3.1）
```

在 3.1.1 说明文字中，把"右侧类型图例侧栏（可隐藏）；无 Inspector"改为"右侧分页侧栏（图例/详情，可隐藏）；无 Inspector"。

- [ ] **Step 3: 最终构建验证**

Run:
```bash
cd /Users/gwm/code/CubeCleaner && ./build.sh build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` / `[SUCCESS]`

- [ ] **Step 4: Commit**

```bash
git -C /Users/gwm/code/CubeCleaner add README.md docs/Interface-Design.md
git -C /Users/gwm/code/CubeCleaner commit -m "docs: 同步 v0.3.1 详情侧栏/删除/钻取刷新到 README 与 Interface-Design

状态升 v0.3.1，Features 补详情侧栏分页/移废纸篓/钻取统计刷新，
交互补侧栏分页与删除说明。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review 记录

- **Spec coverage**：spec §2 布局 → Task 5+7；§3.1 侧栏分页 → Task 5+7 Step6；§3.2 DetailsSidebarView → Task 4；§3.3 钻取统计刷新 → Task 2（纯函数）+ Task 7 Step2/3；§3.4 删除按钮+确认 → Task 3（trashAndRescan）+ Task 6（ActionsView）+ Task 7 Step7（confirmationDialog）+ Task 7 Step8（scanRootURL）；§3.5 entitlements → Task 1；§4 文件清单全覆盖；§6 文档 → Task 8。无遗漏。
- **Placeholder scan**：无 TBD/TODO。Task 4/5/6 显式标注中间构建预期签名错误（跨任务依赖），非占位。
- **Type consistency**：`SidebarTab`（Task 5 定义）在 Task 7 使用一致；`DetailsSidebarView` 签名（Task 4：`selectedNode: Binding<TreeNode?>`, `fileSystemService`, `scanRootURL`, `onRequestDelete`）在 Task 5 引用一致；`ActionsView` 签名（Task 6：`selectedNode`, `fileSystemService`, `scanRootURL`, `onDelete`）在 Task 4 引用一致；`trashAndRescan(deleteURL:scanRootURL:)`（Task 3）在 Task 7 调用一致；`fileCountInSubtree`/`folderCountInSubtree`（Task 2）在 Task 7 调用一致。
- **跨任务构建预期**：Task 4 引用新 ActionsView 签名 → Task 6 才改 ActionsView 定义；Task 5 引用 DetailsSidebarView + 旧 ContentView 未传参 → Task 7 才组装。故 Task 4/5/6 末尾构建可能失败于签名/调用点，属预期，以"无新错误、仅跨任务签名/调用点"为准。Task 7 是首个全绿构建点。
