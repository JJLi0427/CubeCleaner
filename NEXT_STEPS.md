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
3. **[完成] 扫描移出主线程** — `FileSystemService` 保留 `@MainActor`（保 `@Published` 安全），但阻塞 IO 与树构建移至 `Task.detached` 后台线程（`nonisolated` 方法），进度节流（50项/100ms）回主线程，最终 `rootNode` 一次性回主线程接收。修复 PR-003（v0.3.3）。
4. **聚合面积守恒的自动化验证** — 补单元测试断言"保留项 + 其他块面积 ≈ 父目录面积"（依赖 P1 测试基建）。

## P1 - 架构 & 可维护性

1. **拆分 CubeCleanerBackend.swift (1261 行)** →
   - `Models/`：`FileSystemItem`、`TreeNode`、`FileType`
   - `Scanning/`：`BulkFileScanner`
   - `Layout/`：`BinaryTreeMapCalculator`、`TreeMapRectangle`、`ColorSchemeManager`
   - `Services/`：`FileSystemService`
2. **拆分 ContentView.swift (670 行)** → `TreeMapCanvasView`、`DetailsPanelView`、`BreadcrumbView`、`ActionsView` 各自独立文件。
3. **补单元测试** — 覆盖：布局面积守恒、聚合阈值逻辑、`getattrlistbulk` buffer 解析、`findRectangleAt` hit-test。
4. **详情面板点击冲突修复** — 外层 `.onTapGesture` 吞掉内部按钮点击，改用背景遮罩或显式按钮命中区。

## P2 - 功能 & 生产化

1. **删除/Trash** — entitlements 加 `com.apple.security.files.user-selected.read-write`，实现移到废纸篓 + 二次确认（FR-031）。
2. **[完成] 硬链接 inode 去重 + 符号链接防环 + 跨挂载点** — `(st_dev, st_ino)` 去重硬链接与 firmlink；符号链接不跟随标叶子；跨挂载点子目录（`statfs` mntonname）不递归，避免大小虚高（FR-006）。详见 docs/Programming-Design.md §5.3。
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
