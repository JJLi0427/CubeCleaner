# CubeCleaner - macOS 磁盘空间分析工具

CubeCleaner 是一个类似 Windows WizTree 的 macOS 应用程序，用于可视化分析磁盘使用情况。

## 当前状态 (v0.1)

✅ **已完成功能:**
- 基础项目架构搭建
- 文件夹选择界面
- 简单的用户界面布局
- 基础的文件系统访问权限设置

🚧 **开发中的功能:**
- 文件系统扫描后端服务
- TreeMap 可视化算法
- 文件类型颜色编码
- 扫描进度显示

📋 **计划功能:**
- 交互式 TreeMap 界面
- 文件详细信息显示
- 导出扫描结果
- 文件删除功能
- 快速导航

## 项目结构

```
CubeCleaner/
├── CubeCleaner/
│   ├── ContentView.swift          # 主界面
│   ├── CubeCleanerApp.swift       # 应用入口
│   ├── CubeCleaner.entitlements   # 权限配置
│   └── Service/
│       └── CubeCleanerBackend.swift   # 后端服务（完整实现）
├── docs/                          # 设计文档
└── README.md
```

## 后端架构

`CubeCleanerBackend.swift` 包含完整的后端实现：

### 核心组件

1. **FileSystemItem** - 文件系统项目数据模型
2. **TreeNode** - 树形结构节点
3. **FileSystemService** - 文件系统扫描服务
4. **ColorSchemeManager** - 颜色方案管理
5. **TreeMapLayoutCalculator** - TreeMap 布局算法
6. **TreeMapRectangle** - 可视化矩形结构

### 主要功能

- **异步文件扫描**: 支持后台扫描大型目录
- **进度跟踪**: 实时显示扫描进度
- **内存优化**: 限制扫描深度防止内存溢出
- **错误处理**: 优雅处理文件访问权限问题
- **取消机制**: 支持用户取消长时间扫描

## 构建说明

### 环境要求
- macOS 15.5+
- Xcode 16.0+
- Swift 5.0+

### 构建步骤

1. 克隆项目
```bash
git clone <repository-url>
cd CubeCleaner
```

2. 构建项目
```bash
xcodebuild -project CubeCleaner.xcodeproj -scheme CubeCleaner -configuration Debug build
```

3. 运行应用
```bash
open /Users/tangmaocheng/Library/Developer/Xcode/DerivedData/CubeCleaner-*/Build/Products/Debug/CubeCleaner.app
```

## 下一步开发计划

1. **集成后端到前端**: 将完整的后端服务集成到 ContentView
2. **TreeMap 可视化**: 实现交互式的文件大小可视化
3. **性能优化**: 优化大型目录的扫描性能
4. **用户体验**: 添加文件操作和导航功能

## 技术特点

- **SwiftUI 界面**: 现代化的用户界面框架
- **Combine 响应式编程**: 异步数据流处理
- **FileManager 集成**: 原生文件系统访问
- **安全沙盒**: 符合 macOS 安全要求
- **模块化架构**: 清晰的代码组织结构

## 许可证

[待定]

---

*注: 这是一个早期开发版本，还在持续开发中。*
