//
//  CubeCleanerApp.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

@main
struct CubeCleanerApp: App {
    @StateObject private var scannerViewModel = ScannerViewModel()
    @StateObject private var visualizationViewModel = VisualizationViewModel()
    @StateObject private var aiAnalysisViewModel = AIAnalysisViewModel()
    
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("colorScheme") private var colorScheme: String = "fileType"
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scannerViewModel)
                .environmentObject(visualizationViewModel)
                .environmentObject(aiAnalysisViewModel)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Set up initial app state
                    setupAppearance()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            // Add custom menu commands
            SidebarCommands()
            
            CommandGroup(replacing: .newItem) {
                Button("New Scan") {
                    scannerViewModel.prepareForNewScan()
                }
                .keyboardShortcut("n")
            }
            
            CommandMenu("Visualization") {
                Button("Zoom In") {
                    visualizationViewModel.zoomIn()
                }
                .keyboardShortcut("+")
                
                Button("Zoom Out") {
                    visualizationViewModel.zoomOut()
                }
                .keyboardShortcut("-")
                
                Divider()
                
                Menu("Color Scheme") {
                    Button("By File Type") {
                        visualizationViewModel.setColorScheme(.fileType)
                    }
                    .keyboardShortcut("1")
                    
                    Button("By Modification Date") {
                        visualizationViewModel.setColorScheme(.modificationDate)
                    }
                    .keyboardShortcut("2")
                    
                    Button("By Size") {
                        visualizationViewModel.setColorScheme(.size)
                    }
                    .keyboardShortcut("3")
                    
                    Button("By Parent Folder") {
                        visualizationViewModel.setColorScheme(.parentFolder)
                    }
                    .keyboardShortcut("4")
                }
            }
            
            CommandMenu("AI Analysis") {
                Button("Analyze Selected Items") {
                    if let selectedItems = visualizationViewModel.selectedItems {
                        aiAnalysisViewModel.analyzeItems(selectedItems)
                    }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Button("Analyze Current View") {
                    if let currentItems = visualizationViewModel.currentViewItems {
                        aiAnalysisViewModel.analyzeItems(currentItems)
                    }
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
            }
        }
        
        Settings {
            SettingsView()
        }
    }
    
    private func setupAppearance() {
        // Configure app appearance based on user preferences
        switch appTheme {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil // System default
        }
    }
}

// Placeholder for the SettingsView that will be implemented later
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            VisualizationSettingsView()
                .tabItem {
                    Label("Visualization", systemImage: "cube")
                }
            
            AISettingsView()
                .tabItem {
                    Label("AI Integration", systemImage: "brain")
                }
        }
        .padding(20)
        .frame(width: 500, height: 300)
    }
}

// Placeholder for settings tab views
struct GeneralSettingsView: View {
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    var body: some View {
        Form {
            Picker("Appearance", selection: $appTheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding()
    }
}

struct VisualizationSettingsView: View {
    @AppStorage("colorScheme") private var colorScheme: String = "fileType"
    
    var body: some View {
        Form {
            Picker("Default Color Scheme", selection: $colorScheme) {
                Text("File Type").tag("fileType")
                Text("Modification Date").tag("modificationDate")
                Text("Size").tag("size")
                Text("Parent Folder").tag("parentFolder")
            }
            .pickerStyle(RadioGroupPickerStyle())
        }
        .padding()
    }
}

struct AISettingsView: View {
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("enableAI") private var enableAI: Bool = true
    
    var body: some View {
        Form {
            Toggle("Enable AI Analysis", isOn: $enableAI)
            
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Text("The API key is stored securely in your keychain.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}