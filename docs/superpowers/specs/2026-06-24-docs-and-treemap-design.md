# CubeCleaner 文档更新 + TreeMap 算法优化 设计

- **日期**: 2026-06-24
- **当前版本**: v0.2-beta
- **范围**: 重写过时文档、重列下一步计划、优化 TreeMap 可视化算法、顺手修部分架构问题

## 1. 背景

CubeCleaner 已到 v0.2-beta，基础功能跑通，但存在三类问题：

1. **文档与代码严重脱节**。`docs/Programming-Design.md` 描述的是一套完整的 MVVM + 多文件目录结构（`App/ Views/ ViewModels/ Models/ Services/ Utils/ Tests/`），但实际代码是 3 个 Swift 文件，后端逻辑全塞在一个 1223 行的 `CubeCleanerBackend.swift` 里。`NEXT_STEPS.md` 顶部说"v0.2 集成完成"，末尾又写"前端还未集成后端"，自相矛盾。`README.md` 的 Roadmap 全是未勾选状态，与"v0.2 已完成"矛盾。

2. **TreeMap 可视化有过细矩形**。当前 [BinaryTreeMapCalculator](../../CubeCleaner/Service/CubeCleanerBackend.swift) 的 `getValidChildren` 会把 <1% 的子项**直接丢弃**（只保留前 10 大），导致：面积不守恒（子矩形之和 ≠ 父目录大小）；但仍会出现大量细小矩形（保留的子项继续二分到极小区域）。

3. **架构问题积压**：扫描在 `@MainActor` 上跑同步 `getattrlistbulk` 会卡 UI；无测试；有死代码。

本次只解决其中能安全交付的部分，其余记入下一步计划。

## 2. 目标

- 文档照实记录 v0.2 代码现状，并与需求逐条对照标注完成度，消除文档与代码的矛盾。
- TreeMap 消除过细矩形，保证面积守恒，并支持放大后展开长尾。
- 重列下一步计划，分优先级。
- 顺手修复低风险的架构问题（死代码清理），高风险的（扫描移出主线程、拆分大文件）记入计划不在本次动手。

## 3. 非目标（本次不做）

- 不更换布局算法为 Squarified（保留二分法）。
- 不实现删除/Trash 功能（涉及权限变更，放 P2）。
- 不做硬链接 inode 去重、符号链接防环（放 P2）。
- 不拆分大文件、不补测试（放 P1，单独迭代）。
- 不改扫描的主线程问题（放 P0 但单独迭代，本次只记入计划）。

## 4. 设计

### 4.1 文档更新方案

原则：**文档 = 代码现状**，不再描述理想架构。所有"计划中"的功能明确标注。

#### 4.1.1 README.md

- 修正 Roadmap：v0.2 已完成项打勾（基础扫描、TreeMap、详情面板、Finder 集成）。
- 修正"Project Structure"图，反映实际 3 文件结构。
- 补一句 LICENSE 状态说明（仓库暂无 LICENSE 文件，README 声称 MIT 需补文件，本次记入计划）。
- 现状说明改为"v0.2-beta：基础功能可用"。

#### 4.1.2 docs/Requirements.md

- 保留全部需求条目（FR/NF/PR/TC）。
- 在每条需求后追加**状态标记**：✅ 完成 / ⚠️ 部分完成（附说明）/ ❌ 未实现。
- 顶部加"实现状态对照表（截至 v0.2-beta）"说明。
- 标注关键差距：FR-031 删除（❌）、FR-006 硬链接（❌）、PR-003 后台扫描不阻塞 UI（⚠️，当前在主线程）、PR-005 内存 <500MB（⚠️，整棵树常驻内存）。

#### 4.1.3 docs/Interface-Design.md

- 删除虚构的 Sidebar + Inspector 双侧栏布局，改为实际布局：顶部工具栏 + 中央 Canvas + 详情浮层 + 底部状态栏。
- 菜单/快捷键表只列已实现项，未实现标注"计划中"。实际已实现：选择文件夹、取消扫描、点击查看详情、长按在 Finder 中显示。
- 描述实际交互：单击选中、长按 Finder 显示、双击进入子目录（本次新增）、面包屑返回（本次新增）。
- 删除尚未实现的颜色方案切换、缩放平移、多选等描述，移到"计划中"小节。

#### 4.1.4 docs/Programming-Design.md（改动最大）

- 删除虚构的 MVVM 架构图和多文件目录树。
- 改为照实描述 3 文件结构，每个文件用真实代码片段（非伪代码）说明其职责：
  - `CubeCleanerApp.swift`：入口，17 行。
  - `CubeCleanerBackend.swift`：1223 行单文件，按文件内 MARK 分 5 块（扫描器 / 数据模型 / 可视化 / 服务 / 工具），如实说明"单文件过大，计划拆分"。
  - `ContentView.swift`：715 行，含主视图、`TreeMapCanvasView`（Canvas 渲染 + hit-test）、详情面板、子项列表、操作按钮、死代码 `TreeMapRectangleView`。
- 数据流说明：`ContentView` 持有 `FileSystemService`（`@StateObject`）和 `BinaryTreeMapCalculator`（`@State`），扫描完成后调 `updateLayoutOptimized` 在 `Task.detached` 里算布局，回主线程赋值 `rectangles`，Canvas 一次性绘制。
- 性能章节照实写：批量扫描用 `getattrlistbulk`、resize 防抖 0.3s、Canvas 一次性绘制。如实标注"扫描在 `@MainActor` 上，存在卡 UI 风险"。
- 测试章节照实写：当前无测试，计划补布局算法与聚合逻辑的单元测试。

#### 4.1.5 NEXT_STEPS.md

完全重写，删除自相矛盾的旧内容。新结构按第 5 节的 P0/P1/P2 三层。

### 4.2 TreeMap 算法优化（保留二分 + 聚合）

改动集中在 `BinaryTreeMapCalculator` 与 `getValidChildren`，以及 `ContentView` 的交互层。核心思路：**不再丢弃小文件，改为聚合成"其他"块**；放大进入子目录后，子目录总大小更小，长尾自然展开。

#### 4.2.1 聚合"其他"块

替换现有 `getValidChildren` 的"丢弃"逻辑：

- 输入：一个文件夹的 `children: [TreeNode]`。
- 排序：按 `totalSize` 降序。
- 阈值：`threshold = parentTotalSize × aggregateRatio`，`aggregateRatio` 取 **0.005**（0.5%）。
- 保留：所有 `totalSize >= threshold` 的子项。
- 聚合：剩余子项（`totalSize < threshold`）合并为一个**虚拟"其他"节点**：
  - 大小 = 这些子项 `totalSize` 之和（含其递归子项，因为 `totalSize` 是递归的）。
  - 名称 = `"其他 (\(count) 项)"`。
  - 标记 `isAggregated = true`，颜色用中性灰，不参与递归二分（它是叶子矩形）。
- 边界：
  - 若聚合后只剩"其他"（即所有子项都 < 阈值），则不聚合，按现状画（保留前 N 个），避免空图。
  - "其他"块本身不参与"保留前 N 大"的免死金牌逻辑——它就是个汇总叶子。

保证：**保留项 + "其他" 的面积之和 = 父目录大小**，面积守恒。

#### 4.2.2 最小可见面积阈值

`binaryTreeMap` 递归入口已有 `rect.width < minVisibleSize || rect.height < minVisibleSize` 的早退（`minVisibleSize = 24`）。保留。这意味着一旦某分支被分到 <24px 的区域就停止继续二分——但该叶子矩形仍会绘制（占满那个小区域）。配合聚合后，到达这里的小区域基本就是被聚合的大块，不会再有大量细碎叶子。

#### 4.2.3 双击导航进入子目录

- 在 `ContentView` 增加 `@State currentRoot: TreeNode?`，初始 = `fileSystemService.rootNode`。
- `TreeMapCanvasView` 的点击手势扩展：区分单击（选中/详情）与双击（导航）。
  - 双击命中目录节点 → 设 `currentRoot = 该节点`，重算布局（阈值基于新根）。
  - 双击命中文件 → 无操作（或触发 Finder 显示）。
- 布局计算的输入从 `rootNode` 改为 `currentRoot`。
- 长尾展开机制：进入子目录后，`parentTotalSize` = 该子目录大小（远小于根），同一 `aggregateRatio` 下阈值更小，原本被聚合的文件现在满足阈值而独立显示。

#### 4.2.4 面包屑导航

新增 `BreadcrumbView`：

- 显示从扫描根到 `currentRoot` 的路径（用 `TreeNode.parent` 上溯）。
- 每段可点击，点某段则 `currentRoot` 设为该节点并重算。
- 顶部加"返回上级"按钮（`currentRoot.parent`）。
- 面包屑放在工具栏下方一行，不抢 Canvas 空间。

#### 4.2.5 悬停复活

`TreeMapCanvasView` 的 `.onHover { _ in }` 当前是空的，`hoveredRectangle` 从不赋值。改为：在 `DragGesture.onChanged`（或新增 `onGeometryChange`/鼠标移动检测）里更新 `hoveredRectangle`，让 Canvas 绘制时的悬停高亮真正生效。Canvas 内 `drawRectangle` 已读取 `isHovered`，补上赋值即可。

### 4.3 架构问题（本次仅清理死代码）

- 删除 `TreeMapRectangleView`（`ContentView.swift` L429-556），无人引用。
- 清理 `NEXT_STEPS.md` 末尾粘错的目录树片段。
- 其余架构问题（扫描移出主线程、拆分大文件、补测试）记入下一步 P0/P1，不在本次动手。

## 5. 下一步计划（重排，写入 NEXT_STEPS.md）

### P0 - 正确性 & 准确性
1. TreeMap 聚合"其他"块 + 最小可见阈值（本次完成）。
2. 双击进入子目录 + 面包屑导航（本次完成）。
3. 扫描移出主线程：`FileSystemService` 去掉 `@MainActor`，`BulkFileScanner` 在 `Task.detached`/独立 actor 上跑，进度通过 `@Published` 回主线程。
4. 小文件聚合的面积守恒验证（本次完成）+ 边界测试。

### P1 - 架构 & 可维护性
1. 拆分 `CubeCleanerBackend.swift` → `Models/`（`FileSystemItem`、`TreeNode`、`FileType`）+ `Scanning/`（`BulkFileScanner`）+ `Layout/`（`BinaryTreeMapCalculator`、`TreeMapRectangle`、`ColorSchemeManager`）+ `Services/`（`FileSystemService`）。
2. 拆分 `ContentView.swift` → 每个视图组件独立文件（`TreeMapCanvasView`、`DetailsPanelView`、`BreadcrumbView`、`ActionsView`）。
3. 补单元测试：布局算法（面积守恒、阈值聚合、最小可见）、`getattrlistbulk` buffer 解析。
4. 详情面板外层 `.onTapGesture` 与内部按钮冲突修复。

### P2 - 功能 & 生产化
1. 删除/Trash：entitlements 加 `com.apple.security.files.user-selected.read-write`，实现移到废纸篓 + 二次确认。
2. 硬链接 inode 去重、符号链接防环（扫描深度与访问过的 inode 集合双重保护）。
3. 搜索过滤（文件名、大小、类型、日期）。
4. 导出（PNG 图片、CSV/JSON 数据）。
5. 代码签名公证、DMG 打包、LICENSE 文件补齐。
6. 深浅色主题与颜色方案切换完善。

## 6. 变更文件清单

**文档（重写）**
- `README.md`
- `docs/Requirements.md`
- `docs/Interface-Design.md`
- `docs/Programming-Design.md`
- `NEXT_STEPS.md`

**代码（改动）**
- `CubeCleaner/Service/CubeCleanerBackend.swift`：`getValidChildren` 改为聚合逻辑；新增虚拟"其他"节点构造；`BinaryTreeMapCalculator` 接受可变根。
- `CubeCleaner/ContentView.swift`：新增 `currentRoot`、`BreadcrumbView`；`TreeMapCanvasView` 加双击导航、补悬停；删除死代码 `TreeMapRectangleView`。

## 7. 验证

- 文档：逐条核对文档描述与代码一致；需求状态标记与实际功能一致。
- 算法：
  - 手动测一个含大量小文件的目录（如 `node_modules`、`~/Library/Caches`），确认无过细矩形、无空白碎片。
  - 断言"保留项面积 + 其他块面积 ≈ 父目录面积"（人工核对或后续单测）。
  - 双击进入子目录，确认长尾展开为具体文件；面包屑可逐级返回。
- 构建：`./build.sh clean && ./build.sh build` 通过。
