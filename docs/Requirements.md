# CubeCleaner - Requirements Documentation

> **实现状态对照（截至 v0.2-beta）**
> 每条需求后附标记：✅ 完成 / ⚠️ 部分完成 / ❌ 未实现。
> 关键差距：FR-006 硬链接(❌)、FR-031 删除(❌)、PR-003 后台扫描不阻塞UI(❌)、PR-005 内存<500MB(❌)。

## 1. Project Overview

**Project Name:** CubeCleaner  
**Platform:** macOS  
**Programming Language:** Swift (SwiftUI)  
**Target:** Disk usage visualization tool similar to GrandPerspective  

### 1.1 Project Vision
Create a macOS application that provides intuitive visual representation of disk usage through tree map visualization, helping users identify large files and folders to manage disk space effectively.

## 2. Functional Requirements

### 2.1 Core Features

#### 2.1.1 Disk Scanning
- **FR-001**: Scan entire volumes or selected directories ✅
- **FR-002**: Recursively traverse directory structures ✅
- **FR-003**: Calculate file and folder sizes accurately ✅
- **FR-004**: Handle system files and permissions appropriately ⚠️ (有权限拒绝回退，但无统一错误处理)
- **FR-005**: Support scanning of Time Machine backups ❌
- **FR-006**: Handle hard-linked files and folders correctly ❌ (硬链接会重复计算)

#### 2.1.2 Visualization (Tree Map)
- **FR-007**: Display files as rectangles with area proportional to file size ✅
- **FR-008**: Group files within the same folder together ✅
- **FR-009**: Provide smooth zooming and panning capabilities ❌
- **FR-010**: Support animated transitions when navigating ⚠️ (有 layout 动画，无导航过渡)
- **FR-011**: Implement responsive drawing optimized for performance ✅ (Canvas + resize 防抖)

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

#### 2.1.6 Multiple Views Support
- **FR-041**: Support multiple simultaneous views ❌
- **FR-042**: Refresh existing views ✅ (重新扫描)
- **FR-043**: Rescan directories to compare before/after cleanup ⚠️ (可重扫，无对比视图)
- **FR-044**: Twin/duplicate views for different display options ❌
- **FR-045**: Synchronize navigation between related views ❌

#### 2.1.7 Data Persistence
- **FR-046**: Save scan results to disk ❌
- **FR-047**: Load previously saved scan results ❌
- **FR-048**: Export views as images (PNG, JPEG) ❌
- **FR-049**: Export data as text/CSV format ❌
- **FR-050**: Maintain user preferences across sessions ❌

### 2.2 User Interface Requirements

#### 2.2.1 Main Window
- **UI-001**: Resizable main window with minimum size constraints
- **UI-002**: Menu bar with standard macOS menu structure
- **UI-003**: Toolbar with frequently used actions
- **UI-004**: Status bar showing scan progress and statistics
- **UI-005**: Split view with file tree and visualization pane

#### 2.2.2 Visualization Pane
- **UI-006**: Full-screen tree map display
- **UI-007**: Tooltip showing file information on hover
- **UI-008**: Context menu for file operations
- **UI-009**: Zoom controls and indicators
- **UI-010**: Legend showing color coding scheme

#### 2.2.3 Control Panels
- **UI-011**: Color scheme selector
- **UI-012**: Filter configuration panel
- **UI-013**: View options panel
- **UI-014**: Search interface
- **UI-015**: Progress indicators for scanning operations

### 2.3 Performance Requirements

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

## 3. Non-Functional Requirements

### 3.1 Usability Requirements
- **NF-001**: Intuitive interface requiring minimal learning curve
- **NF-002**: Keyboard navigation for accessibility
- **NF-003**: Consistent with macOS Human Interface Guidelines
- **NF-004**: Support for Dark Mode and Light Mode
- **NF-005**: Localization support for multiple languages

### 3.2 Compatibility Requirements
- **NF-006**: macOS 13.0 (Ventura) or later
- **NF-007**: Support Intel and Apple Silicon Macs
- **NF-008**: Compatible with various file systems (APFS, HFS+, exFAT)
- **NF-009**: Handle network volumes and external drives

### 3.3 Security Requirements
- **NF-010**: Request appropriate file system permissions
- **NF-011**: Handle permission denied errors gracefully
- **NF-012**: Secure handling of sensitive file information
- **NF-013**: Sandboxing compliance for App Store distribution

### 3.4 Reliability Requirements
- **NF-014**: Graceful handling of file system errors
- **NF-015**: Recovery from crashed scan operations
- **NF-016**: Memory leak prevention during long-running scans
- **NF-017**: Automatic save of user preferences

## 4. Technical Constraints

### 4.1 Development Constraints
- **TC-001**: Use Swift and SwiftUI as primary technologies
- **TC-002**: Minimum deployment target: macOS 13.0
- **TC-003**: Use Xcode 15.0 or later for development
- **TC-004**: Follow Apple's App Store Review Guidelines
- **TC-005**: Implement proper code signing and notarization

### 4.2 Runtime Constraints
- **TC-006**: Maximum memory usage: 1GB
- **TC-007**: Efficient CPU usage during background operations
- **TC-008**: Minimal disk space for application bundle (<50MB)
- **TC-009**: Support for Retina and non-Retina displays

## 5. User Stories

### 5.1 Primary User Stories
1. **As a user**, I want to scan my disk to see which files are taking up the most space
2. **As a user**, I want to visualize file sizes as colored rectangles to quickly identify large files
3. **As a user**, I want to navigate through folders by clicking on rectangles
4. **As a user**, I want to delete large unnecessary files directly from the visualization
5. **As a user**, I want to filter files by type to focus on specific categories
6. **As a user**, I want to save scan results to compare disk usage over time

### 5.2 Secondary User Stories
1. **As a power user**, I want to create custom filters for advanced file management
2. **As a developer**, I want to scan code repositories to find large build artifacts
3. **As a system administrator**, I want to analyze Time Machine backups for optimization
4. **As a designer**, I want to export visualizations as images for documentation

## 6. Acceptance Criteria

### 6.1 Core Functionality
- [ ] Successfully scan and visualize disk usage for various drive types
- [ ] Accurate file size calculations including proper handling of hard links
- [ ] Smooth and responsive user interface during navigation
- [ ] Complete implementation of all color coding options
- [ ] Functional filtering system with save/load capabilities

### 6.2 Performance Benchmarks
- [ ] Scan 1TB drive with 1M files in under 5 minutes
- [ ] Render visualization with 50K rectangles at 60fps
- [ ] Memory usage remains under 500MB for large datasets
- [ ] Application launches in under 3 seconds

### 6.3 Quality Assurance
- [ ] No crashes during normal operation
- [ ] Proper error handling for permission issues
- [ ] Data integrity maintained across save/load operations
- [ ] Accessibility features work correctly
- [ ] Dark/Light mode transitions work seamlessly

## 7. Future Enhancements

### 7.1 Planned Features
- Network drive scanning optimization
- Cloud storage integration (iCloud, Dropbox)
- Advanced analytics and reporting
- Scripting and automation support
- Plugin system for custom analyzers

### 7.2 Potential Integrations
- Integration with cloud storage services
- Command-line interface for automation
- Web-based report generation
- Integration with backup software
- System monitoring and alerts
