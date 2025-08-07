//
//  VisualizationViewModel.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import SwiftUI
import Combine
import MetalKit

class VisualizationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentScanResult: ScanResult?
    @Published var selectedItem: FileSystemItem?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var colorScheme: ColorScheme = .fileType
    @Published var visualizationMode: VisualizationMode = .cube
    @Published var showHiddenFiles: Bool = false
    @Published var showPackageContents: Bool = false
    @Published var zoomLevel: Float = 1.0
    @Published var currentPath: URL?
    @Published var breadcrumbItems: [FileSystemItem] = []
    @Published var searchText: String = ""
    @Published var searchResults: [FileSystemItem] = []
    @Published var isSearching: Bool = false
    
    // MARK: - Private Properties
    
    private var visualizationEngine: VisualizationEngineProtocol
    private var cancellables = Set<AnyCancellable>()
    private var appPreferences: AppPreferences
    private var metalView: MTKView?
    
    // MARK: - Initialization
    
    init(appPreferences: AppPreferences = AppPreferences.shared) {
        self.appPreferences = appPreferences
        self.visualizationEngine = MetalVisualizationEngine()
        
        // Load preferences
        self.colorScheme = appPreferences.defaultColorScheme
        self.visualizationMode = appPreferences.defaultVisualizationMode
        self.showHiddenFiles = appPreferences.showHiddenFiles
        self.showPackageContents = appPreferences.showPackageContents
        
        // Set up observers
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    func setupMetalView(_ view: MTKView) {
        // Configure Metal view
        view.delegate = visualizationEngine.renderer
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.sampleCount = 1
        view.framebufferOnly = false
        
        self.metalView = view
    }
    
    func visualizeScanResult(_ scanResult: ScanResult) {
        self.isLoading = true
        self.errorMessage = nil
        self.currentScanResult = scanResult
        self.currentPath = scanResult.rootItem.url
        self.breadcrumbItems = [scanResult.rootItem]
        
        // Prepare visualization data on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let visualizationData = self.visualizationEngine.prepareVisualizationData(
                from: scanResult,
                colorScheme: self.colorScheme
            )
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.visualizationEngine.updateVisualization(with: visualizationData)
                self.isLoading = false
                
                // Add to recent scans
                self.appPreferences.addRecentScan(scanResult)
            }
        }
    }
    
    func selectItem(_ item: FileSystemItem?) {
        self.selectedItem = item
        self.visualizationEngine.select(item: item)
    }
    
    func navigateToItem(_ item: FileSystemItem) {
        guard item.isDirectory else {
            // If it's a file, just select it
            selectItem(item)
            return
        }
        
        self.currentPath = item.url
        self.visualizationEngine.zoomTo(item: item)
        
        // Update breadcrumb trail
        if let index = breadcrumbItems.firstIndex(where: { $0.id == item.id }) {
            // If item is already in breadcrumb, truncate to that point
            breadcrumbItems = Array(breadcrumbItems.prefix(through: index))
        } else {
            // Otherwise add to breadcrumb
            breadcrumbItems.append(item)
        }
    }
    
    func navigateUp() {
        guard breadcrumbItems.count > 1 else { return }
        
        // Remove current item and navigate to parent
        breadcrumbItems.removeLast()
        if let parent = breadcrumbItems.last {
            currentPath = parent.url
            visualizationEngine.zoomTo(item: parent)
        }
    }
    
    func resetView() {
        visualizationEngine.resetView()
        
        // Reset breadcrumb to just root
        if let root = currentScanResult?.rootItem {
            breadcrumbItems = [root]
            currentPath = root.url
        }
    }
    
    func changeColorScheme(_ newScheme: ColorScheme) {
        self.colorScheme = newScheme
        
        // Update visualization with new color scheme
        if let scanResult = currentScanResult {
            let visualizationData = visualizationEngine.prepareVisualizationData(
                from: scanResult,
                colorScheme: newScheme
            )
            visualizationEngine.updateVisualization(with: visualizationData)
        }
        
        // Save preference
        appPreferences.defaultColorScheme = newScheme
    }
    
    func changeVisualizationMode(_ newMode: VisualizationMode) {
        self.visualizationMode = newMode
        
        // Update visualization mode
        // In a real implementation, this would switch between different visualization engines
        // or configure the current engine to use a different mode
        
        // Save preference
        appPreferences.defaultVisualizationMode = newMode
    }
    
    func toggleShowHiddenFiles() {
        self.showHiddenFiles.toggle()
        appPreferences.showHiddenFiles = showHiddenFiles
        
        // Refresh visualization if needed
        refreshVisualization()
    }
    
    func toggleShowPackageContents() {
        self.showPackageContents.toggle()
        appPreferences.showPackageContents = showPackageContents
        
        // Refresh visualization if needed
        refreshVisualization()
    }
    
    func search(for text: String) {
        guard !text.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Perform search on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let scanResult = self.currentScanResult else {
                DispatchQueue.main.async {
                    self?.isSearching = false
                }
                return
            }
            
            // Search for items matching the text
            let results = self.searchItems(in: scanResult.rootItem, matching: text)
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    func handleMouseDown(at point: CGPoint) {
        if let engine = visualizationEngine as? MetalVisualizationEngine {
            engine.handleMouseDown(at: point)
        }
    }
    
    func handleMouseDragged(at point: CGPoint) {
        if let engine = visualizationEngine as? MetalVisualizationEngine {
            engine.handleMouseDragged(at: point)
        }
    }
    
    func handleMouseUp() {
        if let engine = visualizationEngine as? MetalVisualizationEngine {
            engine.handleMouseUp()
        }
    }
    
    func handleScroll(delta: CGFloat) {
        if let engine = visualizationEngine as? MetalVisualizationEngine {
            engine.handleScroll(delta: delta)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe changes to selected item from visualization engine
        NotificationCenter.default.publisher(for: .didSelectItem)
            .compactMap { $0.object as? FileSystemItem }
            .receive(on: RunLoop.main)
            .sink { [weak self] item in
                self?.selectedItem = item
            }
            .store(in: &cancellables)
    }
    
    private func refreshVisualization() {
        guard let scanResult = currentScanResult else { return }
        
        // Re-visualize with current settings
        visualizeScanResult(scanResult)
    }
    
    private func searchItems(in item: FileSystemItem, matching text: String) -> [FileSystemItem] {
        var results: [FileSystemItem] = []
        
        // Check if current item matches
        if item.name.localizedCaseInsensitiveContains(text) {
            results.append(item)
        }
        
        // Recursively search children
        if let children = item.children {
            for child in children {
                results.append(contentsOf: searchItems(in: child, matching: text))
            }
        }
        
        return results
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didSelectItem = Notification.Name("VisualizationDidSelectItem")
}