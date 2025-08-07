//
//  ContentView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scannerViewModel: ScannerViewModel
    @EnvironmentObject private var visualizationViewModel: VisualizationViewModel
    @EnvironmentObject private var aiAnalysisViewModel: AIAnalysisViewModel
    
    @State private var showSidebar: Bool = true
    @State private var showDetailPanel: Bool = true
    @State private var searchText: String = ""
    @State private var isScanning: Bool = false
    @State private var showAIPanel: Bool = false
    
    var body: some View {
        NavigationView {
            // Sidebar
            if showSidebar {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: toggleSidebar) {
                                Image(systemName: "sidebar.left")
                            }
                        }
                    }
            }
            
            // Main content area with visualization
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button(action: startScan) {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .help("Start a new disk scan")
                    
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 8)
                    
                    Picker("View", selection: $visualizationViewModel.viewMode) {
                        Text("Cube").tag(VisualizationMode.cube)
                        Text("Treemap").tag(VisualizationMode.treemap)
                        Text("List").tag(VisualizationMode.list)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                    
                    Spacer()
                    
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search files", text: $searchText, onCommit: {
                            visualizationViewModel.searchFiles(searchText)
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                visualizationViewModel.clearSearch()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { showAIPanel.toggle() }) {
                        Label("AI Analysis", systemImage: "brain")
                    }
                    .help("Analyze files with AI to find unused or deletable items")
                    
                    Button(action: { showDetailPanel.toggle() }) {
                        Image(systemName: showDetailPanel ? "sidebar.right" : "sidebar.right.fill")
                    }
                    .help(showDetailPanel ? "Hide detail panel" : "Show detail panel")
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                // Main content with optional detail panel
                HStack(spacing: 0) {
                    // Visualization area
                    ZStack {
                        // Main visualization
                        CubeVisualizationView()
                            .environmentObject(visualizationViewModel)
                        
                        // Scanning overlay
                        if isScanning {
                            ScanningOverlayView(progress: scannerViewModel.scanProgress)
                        }
                        
                        // Empty state
                        if visualizationViewModel.isEmpty && !isScanning {
                            VStack(spacing: 20) {
                                Image(systemName: "cube")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                
                                Text("No scan data available")
                                    .font(.title2)
                                
                                Button("Start Scan", action: startScan)
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    
                    // Detail panel
                    if showDetailPanel {
                        Divider()
                        
                        DetailView()
                            .frame(width: 300)
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .sheet(isPresented: $scannerViewModel.showingScanDialog) {
            ScanDialogView()
                .environmentObject(scannerViewModel)
                .frame(width: 500, height: 300)
        }
        .sheet(isPresented: $showAIPanel) {
            AIRecommendationView()
                .environmentObject(aiAnalysisViewModel)
                .frame(width: 600, height: 500)
        }
        .onReceive(scannerViewModel.$isScanning) { scanning in
            isScanning = scanning
        }
    }
    
    private func toggleSidebar() {
        withAnimation {
            showSidebar.toggle()
        }
    }
    
    private func startScan() {
        scannerViewModel.showingScanDialog = true
    }
}

// Placeholder for the scanning overlay
struct ScanningOverlayView: View {
    var progress: Progress
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            
            VStack(spacing: 20) {
                Text("Scanning disk...")
                    .font(.title2)
                    .foregroundColor(.white)
                
                ProgressView(value: progress.fractionCompleted)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 300)
                
                Text("\(Int(progress.fractionCompleted * 100))%")
                    .foregroundColor(.white)
                
                if let currentPath = progress.localizedDescription {
                    Text(currentPath)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 300)
                }
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.8)))
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// Placeholder for the scan dialog
struct ScanDialogView: View {
    @EnvironmentObject private var scannerViewModel: ScannerViewModel
    @Environment(\.[.presentationMode]) private var presentationMode
    
    @State private var selectedPath: URL? = nil
    @State private var scanDepth: Int = 0 // 0 means unlimited
    @State private var excludeSystemFiles: Bool = true
    @State private var excludeHiddenFiles: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Location to Scan")
                .font(.headline)
            
            HStack {
                Text("Location:")
                
                if let path = selectedPath {
                    Text(path.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No location selected")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Browse...") {
                    selectFolder()
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Options:")
                    .font(.subheadline)
                
                Toggle("Exclude system files", isOn: $excludeSystemFiles)
                Toggle("Exclude hidden files", isOn: $excludeHiddenFiles)
                
                HStack {
                    Text("Scan depth:")
                    
                    Picker("", selection: $scanDepth) {
                        Text("Unlimited").tag(0)
                        Text("1 level").tag(1)
                        Text("2 levels").tag(2)
                        Text("3 levels").tag(3)
                        Text("4 levels").tag(4)
                        Text("5 levels").tag(5)
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                
                Spacer()
                
                Button("Start Scan") {
                    if let path = selectedPath {
                        scannerViewModel.startScan(
                            url: path,
                            excludeSystemFiles: excludeSystemFiles,
                            excludeHiddenFiles: excludeHiddenFiles,
                            depth: scanDepth == 0 ? nil : scanDepth
                        )
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPath == nil)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK {
            selectedPath = openPanel.url
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ScannerViewModel())
            .environmentObject(VisualizationViewModel())
            .environmentObject(AIAnalysisViewModel())
    }
}