# CubeCleaner - Programming Design Documentation

## 1. Architecture Overview

### 1.1 Architectural Pattern
CubeCleaner follows the **MVVM (Model-View-ViewModel)** pattern with **SwiftUI** as the primary UI framework.

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│      Model      │◄───│   ViewModel     │◄───│      View       │
│                 │    │                 │    │     (SwiftUI)   │
│ • FileSystem    │    │ • ScanViewModel │    │ • ContentView   │
│ • TreeNode      │    │ • FilterVM      │    │ • TreeMapView   │
│ • ColorScheme   │    │ • ColorSchemeVM │    │ • SidebarView   │
│ • Filter        │    │ • NavigationVM  │    │ • InspectorView │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 1.2 Core Principles
- **Single Responsibility**: Each class has one clear purpose
- **Dependency Injection**: Testable and modular design
- **Reactive Programming**: Using Combine for data flow
- **Protocol-Oriented**: Extensible through protocols
- **Memory Safety**: Proper memory management and leak prevention

## 2. Project Structure

### 2.1 Directory Organization
```
CubeCleaner/
├── App/
│   ├── CubeCleanerApp.swift
│   ├── AppDelegate.swift
│   └── SceneDelegate.swift
├── Views/
│   ├── ContentView.swift
│   ├── TreeMap/
│   │   ├── TreeMapView.swift
│   │   ├── TreeMapRenderer.swift
│   │   └── TreeMapInteraction.swift
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   ├── VolumeNavigatorView.swift
│   │   └── FilterPanelView.swift
│   ├── Inspector/
│   │   ├── InspectorView.swift
│   │   └── FileDetailsView.swift
│   ├── Dialogs/
│   │   ├── ScanDirectoryView.swift
│   │   ├── ProgressView.swift
│   │   └── PreferencesView.swift
│   └── Components/
│       ├── SearchBar.swift
│       ├── ColorLegend.swift
│       └── ToolbarComponents.swift
├── ViewModels/
│   ├── ScanViewModel.swift
│   ├── TreeMapViewModel.swift
│   ├── FilterViewModel.swift
│   ├── NavigationViewModel.swift
│   └── ColorSchemeViewModel.swift
├── Models/
│   ├── FileSystem/
│   │   ├── FileSystemItem.swift
│   │   ├── TreeNode.swift
│   │   └── VolumeInfo.swift
│   ├── Scanning/
│   │   ├── DirectoryScanner.swift
│   │   ├── ScanResult.swift
│   │   └── ScanProgress.swift
│   ├── Visualization/
│   │   ├── Rectangle.swift
│   │   ├── ColorScheme.swift
│   │   └── Layout.swift
│   └── Filtering/
│       ├── Filter.swift
│       ├── FilterCriteria.swift
│       └── FilterPreset.swift
├── Services/
│   ├── FileSystemService.swift
│   ├── PersistenceService.swift
│   ├── ExportService.swift
│   └── PreferencesService.swift
├── Utils/
│   ├── Extensions/
│   ├── Constants.swift
│   ├── Helpers.swift
│   └── Logger.swift
├── Resources/
│   ├── Assets.xcassets
│   ├── Localizable.strings
│   └── Info.plist
└── Tests/
    ├── UnitTests/
    ├── IntegrationTests/
    └── UITests/
```

## 3. Core Models

### 3.1 FileSystemItem Model
```swift
import Foundation

struct FileSystemItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: URL
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date
    let accessDate: Date
    let fileType: FileType
    let permissions: FilePermissions
    var children: [FileSystemItem]?
    
    // Computed Properties
    var extension: String {
        path.pathExtension.lowercased()
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var isHidden: Bool {
        name.hasPrefix(".")
    }
}

enum FileType: String, CaseIterable {
    case document, image, video, audio, archive, application, system, other
    
    static func from(extension: String) -> FileType {
        // Implementation for file type detection
    }
}

struct FilePermissions {
    let isReadable: Bool
    let isWritable: Bool
    let isExecutable: Bool
}
```

### 3.2 TreeNode Model
```swift
import Foundation

class TreeNode: ObservableObject, Identifiable {
    let id = UUID()
    let item: FileSystemItem
    let parent: TreeNode?
    @Published var children: [TreeNode]
    @Published var isExpanded: Bool = false
    
    // TreeMap specific properties
    var rectangle: CGRect = .zero
    var color: Color = .gray
    var level: Int
    
    init(item: FileSystemItem, parent: TreeNode? = nil) {
        self.item = item
        self.parent = parent
        self.level = (parent?.level ?? -1) + 1
        self.children = []
    }
    
    // Computed properties
    var totalSize: Int64 {
        if item.isDirectory {
            return children.reduce(item.size) { $0 + $1.totalSize }
        }
        return item.size
    }
    
    var depth: Int {
        parent?.depth ?? 0 + 1
    }
    
    var path: [TreeNode] {
        var path: [TreeNode] = []
        var current: TreeNode? = self
        while let node = current {
            path.insert(node, at: 0)
            current = node.parent
        }
        return path
    }
    
    // Navigation methods
    func addChild(_ child: TreeNode) {
        children.append(child)
    }
    
    func removeChild(_ child: TreeNode) {
        children.removeAll { $0.id == child.id }
    }
    
    func find(path: String) -> TreeNode? {
        // Implementation for finding node by path
    }
}
```

### 3.3 Rectangle Model (TreeMap)
```swift
import SwiftUI

struct TreeMapRectangle: Identifiable {
    let id = UUID()
    let node: TreeNode
    let rect: CGRect
    let color: Color
    let borderWidth: CGFloat
    let level: Int
    
    // Interaction state
    var isSelected: Bool = false
    var isHovered: Bool = false
    
    // Display properties
    var shouldShowLabel: Bool {
        rect.width > 50 && rect.height > 20
    }
    
    var labelFont: Font {
        let size = min(rect.width, rect.height) / 10
        return .system(size: max(8, min(size, 16)))
    }
    
    var displayName: String {
        let maxLength = Int(rect.width / 8)
        if node.item.name.count > maxLength {
            return String(node.item.name.prefix(maxLength - 3)) + "..."
        }
        return node.item.name
    }
}
```

## 4. ViewModels

### 4.1 ScanViewModel
```swift
import Foundation
import Combine

@MainActor
class ScanViewModel: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var currentPath: String = ""
    @Published var filesScanned: Int = 0
    @Published var totalSize: Int64 = 0
    @Published var rootNode: TreeNode?
    @Published var scanError: Error?
    
    private let fileSystemService: FileSystemService
    private let persistenceService: PersistenceService
    private var cancellables = Set<AnyCancellable>()
    private var scanTask: Task<Void, Never>?
    
    init(fileSystemService: FileSystemService = .shared,
         persistenceService: PersistenceService = .shared) {
        self.fileSystemService = fileSystemService
        self.persistenceService = persistenceService
    }
    
    func scanDirectory(at url: URL, options: ScanOptions = .default) {
        guard !isScanning else { return }
        
        scanTask = Task {
            await performScan(at: url, options: options)
        }
    }
    
    private func performScan(at url: URL, options: ScanOptions) async {
        isScanning = true
        scanProgress = 0.0
        filesScanned = 0
        totalSize = 0
        scanError = nil
        
        do {
            let scanner = DirectoryScanner(options: options)
            
            scanner.progressPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] progress in
                    self?.scanProgress = progress.percentage
                    self?.currentPath = progress.currentPath
                    self?.filesScanned = progress.filesScanned
                    self?.totalSize = progress.totalSize
                }
                .store(in: &cancellables)
            
            let result = try await scanner.scan(url: url)
            rootNode = result.rootNode
            
        } catch {
            scanError = error
        }
        
        isScanning = false
    }
    
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
    
    func saveScanResult(to url: URL) async throws {
        guard let rootNode = rootNode else { return }
        try await persistenceService.save(rootNode, to: url)
    }
    
    func loadScanResult(from url: URL) async throws {
        rootNode = try await persistenceService.load(from: url)
    }
}

struct ScanOptions {
    let includeHiddenFiles: Bool
    let followSymlinks: Bool
    let scanPackageContents: Bool
    let maxDepth: Int?
    
    static let `default` = ScanOptions(
        includeHiddenFiles: false,
        followSymlinks: false,
        scanPackageContents: true,
        maxDepth: nil
    )
}
```

### 4.2 TreeMapViewModel
```swift
import SwiftUI
import Combine

@MainActor
class TreeMapViewModel: ObservableObject {
    @Published var rectangles: [TreeMapRectangle] = []
    @Published var selectedNode: TreeNode?
    @Published var hoveredNode: TreeNode?
    @Published var currentRoot: TreeNode?
    @Published var zoomLevel: Double = 1.0
    @Published var panOffset: CGPoint = .zero
    @Published var colorScheme: ColorSchemeType = .fileType
    
    private let layoutCalculator: TreeMapLayoutCalculator
    private let colorSchemeManager: ColorSchemeManager
    private var cancellables = Set<AnyCancellable>()
    
    var navigationPath: [TreeNode] {
        currentRoot?.path ?? []
    }
    
    init(layoutCalculator: TreeMapLayoutCalculator = .init(),
         colorSchemeManager: ColorSchemeManager = .shared) {
        self.layoutCalculator = layoutCalculator
        self.colorSchemeManager = colorSchemeManager
    }
    
    func setRootNode(_ node: TreeNode?) {
        currentRoot = node
        calculateLayout()
    }
    
    func navigateToNode(_ node: TreeNode) {
        guard node.item.isDirectory else { return }
        currentRoot = node
        selectedNode = nil
        resetZoomAndPan()
        calculateLayout()
    }
    
    func navigateUp() {
        guard let parent = currentRoot?.parent else { return }
        navigateToNode(parent)
    }
    
    func selectNode(_ node: TreeNode) {
        selectedNode = node
        updateRectangleSelection()
    }
    
    func setHoveredNode(_ node: TreeNode?) {
        hoveredNode = node
        updateRectangleHover()
    }
    
    private func calculateLayout() {
        guard let root = currentRoot else {
            rectangles = []
            return
        }
        
        let availableRect = CGRect(x: 0, y: 0, width: 1000, height: 800) // Will be updated with actual size
        let calculatedRectangles = layoutCalculator.calculateLayout(
            for: root,
            in: availableRect,
            colorScheme: colorScheme
        )
        
        rectangles = calculatedRectangles.map { rect in
            TreeMapRectangle(
                node: rect.node,
                rect: rect.frame,
                color: colorSchemeManager.color(for: rect.node, scheme: colorScheme),
                borderWidth: 1.0,
                level: rect.level
            )
        }
    }
    
    func updateLayout(for size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        // Recalculate layout with new size
        calculateLayout()
    }
    
    private func updateRectangleSelection() {
        for i in rectangles.indices {
            rectangles[i].isSelected = rectangles[i].node.id == selectedNode?.id
        }
    }
    
    private func updateRectangleHover() {
        for i in rectangles.indices {
            rectangles[i].isHovered = rectangles[i].node.id == hoveredNode?.id
        }
    }
    
    private func resetZoomAndPan() {
        zoomLevel = 1.0
        panOffset = .zero
    }
}
```

## 5. Services

### 5.1 FileSystemService
```swift
import Foundation
import Combine

actor FileSystemService {
    static let shared = FileSystemService()
    
    private init() {}
    
    func getVolumeInfo() async throws -> [VolumeInfo] {
        let fileManager = FileManager.default
        let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ]
        ) ?? []
        
        var volumes: [VolumeInfo] = []
        
        for url in volumeURLs {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            
            let info = VolumeInfo(
                name: resourceValues.volumeName ?? "Unknown",
                url: url,
                totalCapacity: resourceValues.volumeTotalCapacity ?? 0,
                availableCapacity: resourceValues.volumeAvailableCapacity ?? 0
            )
            volumes.append(info)
        }
        
        return volumes
    }
    
    func getDirectoryContents(at url: URL, options: ScanOptions) async throws -> [FileSystemItem] {
        let fileManager = FileManager.default
        
        let resourceKeys: [URLResourceKey] = [
            .nameKey,
            .fileSizeKey,
            .isDirectoryKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .isHiddenKey,
            .fileResourceTypeKey
        ]
        
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: options.includeHiddenFiles ? [] : [.skipsHiddenFiles]
        )
        
        var items: [FileSystemItem] = []
        
        for itemURL in contents {
            do {
                let resourceValues = try itemURL.resourceValues(forKeys: Set(resourceKeys))
                
                let item = FileSystemItem(
                    name: resourceValues.name ?? itemURL.lastPathComponent,
                    path: itemURL,
                    size: Int64(resourceValues.fileSize ?? 0),
                    isDirectory: resourceValues.isDirectory ?? false,
                    creationDate: resourceValues.creationDate ?? Date(),
                    modificationDate: resourceValues.contentModificationDate ?? Date(),
                    accessDate: resourceValues.contentAccessDate ?? Date(),
                    fileType: FileType.from(extension: itemURL.pathExtension),
                    permissions: FilePermissions(
                        isReadable: fileManager.isReadableFile(atPath: itemURL.path),
                        isWritable: fileManager.isWritableFile(atPath: itemURL.path),
                        isExecutable: fileManager.isExecutableFile(atPath: itemURL.path)
                    )
                )
                
                items.append(item)
            } catch {
                // Log error and continue with other items
                Logger.shared.warning("Failed to read item at \(itemURL): \(error)")
            }
        }
        
        return items
    }
    
    func deleteItem(at url: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }
    
    func revealInFinder(url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
}
```

### 5.2 DirectoryScanner
```swift
import Foundation
import Combine

actor DirectoryScanner {
    private let options: ScanOptions
    private let progressSubject = PassthroughSubject<ScanProgress, Never>()
    private var isCancelled = false
    
    var progressPublisher: AnyPublisher<ScanProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    init(options: ScanOptions) {
        self.options = options
    }
    
    func scan(url: URL) async throws -> ScanResult {
        isCancelled = false
        let startTime = Date()
        
        let rootItem = try await FileSystemService.shared.getDirectoryContents(at: url, options: options).first { $0.path == url }
        guard let rootItem = rootItem else {
            throw ScanError.invalidPath
        }
        
        let rootNode = TreeNode(item: rootItem)
        var totalFilesScanned = 0
        var totalSize: Int64 = 0
        
        try await scanRecursively(
            node: rootNode,
            currentDepth: 0,
            totalFilesScanned: &totalFilesScanned,
            totalSize: &totalSize
        )
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        return ScanResult(
            rootNode: rootNode,
            totalFiles: totalFilesScanned,
            totalSize: totalSize,
            scanDuration: duration,
            scanDate: endTime
        )
    }
    
    private func scanRecursively(
        node: TreeNode,
        currentDepth: Int,
        totalFilesScanned: inout Int,
        totalSize: inout Int64
    ) async throws {
        guard !isCancelled else { throw ScanError.cancelled }
        
        if let maxDepth = options.maxDepth, currentDepth >= maxDepth {
            return
        }
        
        guard node.item.isDirectory else {
            totalFilesScanned += 1
            totalSize += node.item.size
            
            let progress = ScanProgress(
                currentPath: node.item.path.path,
                filesScanned: totalFilesScanned,
                totalSize: totalSize,
                percentage: 0.0 // Calculate based on estimated total
            )
            progressSubject.send(progress)
            return
        }
        
        do {
            let contents = try await FileSystemService.shared.getDirectoryContents(
                at: node.item.path,
                options: options
            )
            
            for item in contents {
                let childNode = TreeNode(item: item, parent: node)
                node.addChild(childNode)
                
                try await scanRecursively(
                    node: childNode,
                    currentDepth: currentDepth + 1,
                    totalFilesScanned: &totalFilesScanned,
                    totalSize: &totalSize
                )
            }
        } catch {
            // Log error and continue
            Logger.shared.warning("Failed to scan directory \(node.item.path): \(error)")
        }
    }
    
    func cancel() {
        isCancelled = true
    }
}

struct ScanProgress {
    let currentPath: String
    let filesScanned: Int
    let totalSize: Int64
    let percentage: Double
}

struct ScanResult {
    let rootNode: TreeNode
    let totalFiles: Int
    let totalSize: Int64
    let scanDuration: TimeInterval
    let scanDate: Date
}

enum ScanError: Error {
    case invalidPath
    case permissionDenied
    case cancelled
    case diskError(Error)
}
```

## 6. Layout Algorithm

### 6.1 TreeMapLayoutCalculator
```swift
import SwiftUI

class TreeMapLayoutCalculator {
    
    func calculateLayout(for node: TreeNode, in rect: CGRect, colorScheme: ColorSchemeType) -> [LayoutItem] {
        var items: [LayoutItem] = []
        
        if node.children.isEmpty {
            // Leaf node - create rectangle
            items.append(LayoutItem(
                node: node,
                frame: rect,
                level: node.level
            ))
        } else {
            // Directory - subdivide space
            let sortedChildren = node.children.sorted { $0.totalSize > $1.totalSize }
            let childItems = squarify(children: sortedChildren, in: rect, level: node.level + 1)
            items.append(contentsOf: childItems)
        }
        
        return items
    }
    
    private func squarify(children: [TreeNode], in rect: CGRect, level: Int) -> [LayoutItem] {
        guard !children.isEmpty else { return [] }
        
        let totalSize = children.reduce(0) { $0 + $1.totalSize }
        guard totalSize > 0 else { return [] }
        
        var items: [LayoutItem] = []
        var remaining = children
        var currentRect = rect
        
        while !remaining.isEmpty {
            let (row, rest) = getBestRow(nodes: remaining, in: currentRect, totalSize: totalSize)
            
            // Layout this row
            let rowItems = layoutRow(row: row, in: getRowRect(in: currentRect, isVertical: currentRect.height > currentRect.width), level: level)
            items.append(contentsOf: rowItems)
            
            // Update remaining rect
            currentRect = getRemainingRect(from: currentRect, after: row, totalSize: totalSize)
            remaining = rest
        }
        
        return items
    }
    
    private func getBestRow(nodes: [TreeNode], in rect: CGRect, totalSize: Int64) -> ([TreeNode], [TreeNode]) {
        guard !nodes.isEmpty else { return ([], []) }
        
        var bestRow: [TreeNode] = [nodes[0]]
        var bestAspectRatio = Double.infinity
        
        for i in 1..<nodes.count {
            let currentRow = Array(nodes[0...i])
            let aspectRatio = calculateWorstAspectRatio(for: currentRow, in: rect, totalSize: totalSize)
            
            if aspectRatio < bestAspectRatio {
                bestRow = currentRow
                bestAspectRatio = aspectRatio
            } else {
                break // Aspect ratio is getting worse
            }
        }
        
        let remaining = Array(nodes[bestRow.count...])
        return (bestRow, remaining)
    }
    
    private func calculateWorstAspectRatio(for row: [TreeNode], in rect: CGRect, totalSize: Int64) -> Double {
        let rowSize = row.reduce(0) { $0 + $1.totalSize }
        let rectArea = rect.width * rect.height
        let rowArea = rectArea * CGFloat(rowSize) / CGFloat(totalSize)
        
        let isVertical = rect.height > rect.width
        let length = isVertical ? rect.width : rect.height
        let rowThickness = rowArea / length
        
        var worstRatio = 0.0
        
        for node in row {
            let nodeArea = rowArea * CGFloat(node.totalSize) / CGFloat(rowSize)
            let nodeLength = nodeArea / rowThickness
            
            let ratio = max(nodeLength / rowThickness, rowThickness / nodeLength)
            worstRatio = max(worstRatio, Double(ratio))
        }
        
        return worstRatio
    }
    
    private func layoutRow(row: [TreeNode], in rect: CGRect, level: Int) -> [LayoutItem] {
        var items: [LayoutItem] = []
        let totalSize = row.reduce(0) { $0 + $1.totalSize }
        
        var currentX = rect.minX
        let y = rect.minY
        let height = rect.height
        
        for node in row {
            let width = rect.width * CGFloat(node.totalSize) / CGFloat(totalSize)
            let nodeRect = CGRect(x: currentX, y: y, width: width, height: height)
            
            if node.children.isEmpty {
                items.append(LayoutItem(node: node, frame: nodeRect, level: level))
            } else {
                // Recursively layout children
                let childItems = calculateLayout(for: node, in: nodeRect, colorScheme: .fileType)
                items.append(contentsOf: childItems)
            }
            
            currentX += width
        }
        
        return items
    }
    
    private func getRowRect(in rect: CGRect, isVertical: Bool) -> CGRect {
        if isVertical {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5)
        } else {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.5, height: rect.height)
        }
    }
    
    private func getRemainingRect(from rect: CGRect, after row: [TreeNode], totalSize: Int64) -> CGRect {
        let rowSize = row.reduce(0) { $0 + $1.totalSize }
        let ratio = CGFloat(rowSize) / CGFloat(totalSize)
        
        if rect.height > rect.width {
            let usedHeight = rect.height * ratio
            return CGRect(x: rect.minX, y: rect.minY + usedHeight, width: rect.width, height: rect.height - usedHeight)
        } else {
            let usedWidth = rect.width * ratio
            return CGRect(x: rect.minX + usedWidth, y: rect.minY, width: rect.width - usedWidth, height: rect.height)
        }
    }
}

struct LayoutItem {
    let node: TreeNode
    let frame: CGRect
    let level: Int
}
```

## 7. Key Views Implementation

### 7.1 TreeMapView
```swift
import SwiftUI

struct TreeMapView: View {
    @StateObject private var viewModel: TreeMapViewModel
    @State private var dragOffset: CGSize = .zero
    @State private var lastScaleValue: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(.controlBackgroundColor)
                
                // TreeMap Rectangles
                ForEach(viewModel.rectangles) { rectangle in
                    TreeMapRectangleView(
                        rectangle: rectangle,
                        onTap: { viewModel.selectNode(rectangle.node) },
                        onDoubleTap: { viewModel.navigateToNode(rectangle.node) },
                        onHover: { isHovered in
                            viewModel.setHoveredNode(isHovered ? rectangle.node : nil)
                        }
                    )
                    .scaleEffect(viewModel.zoomLevel)
                    .offset(x: viewModel.panOffset.x + dragOffset.width,
                           y: viewModel.panOffset.y + dragOffset.height)
                }
                
                // Navigation Breadcrumb
                VStack {
                    HStack {
                        BreadcrumbView(path: viewModel.navigationPath) { node in
                            viewModel.navigateToNode(node)
                        }
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            }
            .gesture(
                SimultaneousGesture(
                    // Pan Gesture
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            viewModel.panOffset.x += value.translation.x
                            viewModel.panOffset.y += value.translation.y
                            dragOffset = .zero
                        },
                    
                    // Zoom Gesture
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScaleValue
                            lastScaleValue = value
                            viewModel.zoomLevel *= delta
                        }
                        .onEnded { value in
                            lastScaleValue = 1.0
                        }
                )
            )
            .onAppear {
                viewModel.updateLayout(for: geometry.size)
            }
            .onChange(of: geometry.size) { newSize in
                viewModel.updateLayout(for: newSize)
            }
        }
    }
}

struct TreeMapRectangleView: View {
    let rectangle: TreeMapRectangle
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(rectangle.color)
                .border(Color.primary.opacity(0.3), width: rectangle.borderWidth)
                .brightness(rectangle.isHovered ? 0.1 : 0)
                .overlay(
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: rectangle.isSelected ? 2 : 0)
                )
            
            if rectangle.shouldShowLabel {
                Text(rectangle.displayName)
                    .font(rectangle.labelFont)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: rectangle.rect.width, height: rectangle.rect.height)
        .position(x: rectangle.rect.midX, y: rectangle.rect.midY)
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .onHover { isHovered in
            onHover(isHovered)
        }
        .contextMenu {
            ContextMenuView(node: rectangle.node)
        }
    }
}
```

## 8. Testing Strategy

### 8.1 Unit Tests
```swift
import XCTest
@testable import CubeCleaner

class TreeMapLayoutCalculatorTests: XCTestCase {
    var calculator: TreeMapLayoutCalculator!
    
    override func setUp() {
        super.setUp()
        calculator = TreeMapLayoutCalculator()
    }
    
    func testSingleFileLayout() {
        let item = FileSystemItem(
            name: "test.txt",
            path: URL(fileURLWithPath: "/test.txt"),
            size: 1000,
            isDirectory: false,
            // ... other properties
        )
        let node = TreeNode(item: item)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        let result = calculator.calculateLayout(for: node, in: rect, colorScheme: .fileType)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].frame, rect)
        XCTAssertEqual(result[0].node.id, node.id)
    }
    
    func testDirectoryLayout() {
        // Create test directory structure
        let parentItem = FileSystemItem(name: "parent", path: URL(fileURLWithPath: "/parent"), size: 0, isDirectory: true, /* ... */)
        let parentNode = TreeNode(item: parentItem)
        
        let child1Item = FileSystemItem(name: "file1.txt", path: URL(fileURLWithPath: "/parent/file1.txt"), size: 500, isDirectory: false, /* ... */)
        let child1Node = TreeNode(item: child1Item, parent: parentNode)
        
        let child2Item = FileSystemItem(name: "file2.txt", path: URL(fileURLWithPath: "/parent/file2.txt"), size: 1500, isDirectory: false, /* ... */)
        let child2Node = TreeNode(item: child2Item, parent: parentNode)
        
        parentNode.addChild(child1Node)
        parentNode.addChild(child2Node)
        
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = calculator.calculateLayout(for: parentNode, in: rect, colorScheme: .fileType)
        
        XCTAssertEqual(result.count, 2)
        
        // Larger file should have larger area
        let file1Rect = result.first { $0.node.item.name == "file1.txt" }?.frame
        let file2Rect = result.first { $0.node.item.name == "file2.txt" }?.frame
        
        XCTAssertNotNil(file1Rect)
        XCTAssertNotNil(file2Rect)
        XCTAssertLessThan(file1Rect!.width * file1Rect!.height, file2Rect!.width * file2Rect!.height)
    }
}
```

### 8.2 Integration Tests
```swift
class ScanViewModelIntegrationTests: XCTestCase {
    var viewModel: ScanViewModel!
    var mockFileSystemService: MockFileSystemService!
    
    override func setUp() {
        super.setUp()
        mockFileSystemService = MockFileSystemService()
        viewModel = ScanViewModel(fileSystemService: mockFileSystemService)
    }
    
    func testFullScanWorkflow() async {
        // Setup mock data
        let testURL = URL(fileURLWithPath: "/test")
        mockFileSystemService.setupMockFileSystem()
        
        // Start scan
        viewModel.scanDirectory(at: testURL)
        
        // Wait for completion
        await waitForScanCompletion()
        
        // Verify results
        XCTAssertNotNil(viewModel.rootNode)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertGreaterThan(viewModel.filesScanned, 0)
        XCTAssertGreaterThan(viewModel.totalSize, 0)
    }
    
    private func waitForScanCompletion() async {
        while viewModel.isScanning {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
}
```

## 9. Performance Optimization

### 9.1 Memory Management
- Use weak references to prevent retain cycles
- Implement lazy loading for large directory trees
- Use value types where appropriate
- Regular memory profiling with Instruments

### 9.2 Rendering Optimization
- Implement viewport culling for large visualizations
- Use background queues for layout calculations
- Cache calculated rectangles
- Optimize redraw regions

### 9.3 Scanning Optimization
- Use FileManager enumerator for efficient traversal
- Implement cancellation tokens
- Batch progress updates
- Use concurrent queues for independent operations

## 10. Error Handling

### 10.1 Error Types
```swift
enum CubeCleanerError: LocalizedError {
    case fileSystemPermissionDenied(path: String)
    case scanCancelled
    case invalidFileFormat
    case diskFull
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .fileSystemPermissionDenied(let path):
            return "Permission denied for path: \(path)"
        case .scanCancelled:
            return "Scan operation was cancelled"
        case .invalidFileFormat:
            return "Invalid file format"
        case .diskFull:
            return "Insufficient disk space"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
```

### 10.2 Error Recovery
- Graceful degradation for permission errors
- Retry mechanisms for network operations
- User-friendly error messages
- Logging for debugging purposes

This comprehensive programming design documentation provides the foundation for implementing CubeCleaner with proper architecture, performance, and maintainability considerations.
