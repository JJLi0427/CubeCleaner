//
//  MainView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct MainView: View {
    @StateObject private var scannerViewModel = ScannerViewModel()
    @StateObject private var visualizationViewModel = VisualizationViewModel()
    @StateObject private var aiAnalysisViewModel = AIAnalysisViewModel()
    @EnvironmentObject private var appPreferences: AppPreferences
    
    @State private var selectedTab = 0
    @State private var showFolderPicker = false
    @State private var showSaveDialog = false
    @State private var showLoadDialog = false
    @State private var showAPIKeySheet = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Scan Tab
            ScanView(viewModel: scannerViewModel)
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(0)
            
            // Visualization Tab
            VisualizationView(viewModel: visualizationViewModel)
                .tabItem {
                    Label("Visualize", systemImage: "cube")
                }
                .tag(1)
            
            // AI Analysis Tab
            AIAnalysisView(viewModel: aiAnalysisViewModel)
                .tabItem {
                    Label("AI Analysis", systemImage: "brain")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView(preferences: appPreferences)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .onAppear {
            setupViewModelConnections()
            setupNotificationObservers()
        }
        .onChange(of: scannerViewModel.currentScanResult) { newScanResult in
            if let result = newScanResult {
                visualizationViewModel.setScanResult(result)
                aiAnalysisViewModel.setScanResult(result)
            }
        }
        // File picker for new scan
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        // File exporter for saving scan
        .fileExporter(
            isPresented: $showSaveDialog,
            document: ScanResultDocument(scanResult: scannerViewModel.currentScanResult),
            contentType: .json,
            defaultFilename: "Scan_\(Date().formatted(date: .numeric, time: .omitted))"
        ) { _ in }
        // File importer for loading scan
        .fileImporter(
            isPresented: $showLoadDialog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        // Sheet for API key configuration
        .sheet(isPresented: $showAPIKeySheet) {
            APIKeyConfigView(viewModel: aiAnalysisViewModel)
        }
    }
    
    private func setupViewModelConnections() {
        // Connect scan results to visualization and AI analysis
        if let currentScan = scannerViewModel.currentScanResult {
            visualizationViewModel.setScanResult(currentScan)
            aiAnalysisViewModel.setScanResult(currentScan)
        }
        
        // Listen for item selection in scan view
        NotificationCenter.default.addObserver(
            forName: .didSelectScanItem,
            object: nil,
            queue: .main
        ) { notification in
            if let item = notification.object as? FileSystemItem {
                // Switch to visualization tab and select the item
                selectedTab = 1
                visualizationViewModel.selectItem(item)
            }
        }
        
        // Listen for item selection in AI analysis view
        NotificationCenter.default.addObserver(
            forName: .didSelectAnalysisItem,
            object: nil,
            queue: .main
        ) { notification in
            if let item = notification.object as? FileSystemItem {
                // Switch to visualization tab and select the item
                selectedTab = 1
                visualizationViewModel.selectItem(item)
            }
        }
    }
    
    private func setupNotificationObservers() {
        // Menu command notifications
        NotificationCenter.default.addObserver(
            forName: .newScan,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = 0 // Switch to scan tab
            showFolderPicker = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .stopScan,
            object: nil,
            queue: .main
        ) { _ in
            scannerViewModel.cancelScan()
        }
        
        NotificationCenter.default.addObserver(
            forName: .saveScan,
            object: nil,
            queue: .main
        ) { _ in
            if scannerViewModel.currentScanResult != nil {
                showSaveDialog = true
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .loadScan,
            object: nil,
            queue: .main
        ) { _ in
            showLoadDialog = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .resetVisualization,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = 1 // Switch to visualization tab
            visualizationViewModel.resetView()
        }
        
        NotificationCenter.default.addObserver(
            forName: .setColorScheme,
            object: nil,
            queue: .main
        ) { notification in
            if let colorScheme = notification.object as? ColorScheme {
                selectedTab = 1 // Switch to visualization tab
                visualizationViewModel.setColorScheme(colorScheme)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .analyzeCurrentScan,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = 2 // Switch to AI analysis tab
            aiAnalysisViewModel.analyzeCurrentScan()
        }
        
        NotificationCenter.default.addObserver(
            forName: .showSettings,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = 3 // Switch to settings tab
        }
        
        NotificationCenter.default.addObserver(
            forName: .showAPIKeyConfig,
            object: nil,
            queue: .main
        ) { _ in
            showAPIKeySheet = true
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            
            // Start scan with selected folder
            scannerViewModel.startScan(path: selectedURL)
            
        case .failure(let error):
            scannerViewModel.errorMessage = "Failed to select folder: \(error.localizedDescription)"
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            
            // Load scan result from file
            Task {
                _ = await scannerViewModel.loadScanResultFromFile(at: selectedURL)
            }
            
        case .failure(let error):
            scannerViewModel.errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didSelectAnalysisItem = Notification.Name("AIAnalysisViewDidSelectItem")
}

// MARK: - Preview

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}