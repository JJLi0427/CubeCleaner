//
//  CubeCleanerApp.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

@main
struct CubeCleanerApp: App {
    @StateObject private var appPreferences = AppPreferences.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(appPreferences)
                .onAppear {
                    setupApp()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            SidebarCommands()
            ToolbarCommands()
            
            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    openPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Scan") {
                Button("New Scan...") {
                    NotificationCenter.default.post(name: .newScan, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Stop Scan") {
                    NotificationCenter.default.post(name: .stopScan, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
                
                Divider()
                
                Button("Save Scan Results...") {
                    NotificationCenter.default.post(name: .saveScan, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button("Load Scan Results...") {
                    NotificationCenter.default.post(name: .loadScan, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandMenu("Visualization") {
                Button("Reset View") {
                    NotificationCenter.default.post(name: .resetVisualization, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Color by File Type") {
                    NotificationCenter.default.post(name: .setColorScheme, object: ColorScheme.fileType)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Color by Modification Date") {
                    NotificationCenter.default.post(name: .setColorScheme, object: ColorScheme.modificationDate)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Color by Size") {
                    NotificationCenter.default.post(name: .setColorScheme, object: ColorScheme.size)
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("Color by Parent Folder") {
                    NotificationCenter.default.post(name: .setColorScheme, object: ColorScheme.parentFolder)
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Divider()
                
                Button("Show Hidden Files") {
                    appPreferences.showHiddenFiles.toggle()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                
                Button("Show Package Contents") {
                    appPreferences.showPackageContents.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            
            CommandMenu("AI Analysis") {
                Button("Analyze Current Scan") {
                    NotificationCenter.default.post(name: .analyzeCurrentScan, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Button("Configure API Key") {
                    NotificationCenter.default.post(name: .showAPIKeyConfig, object: nil)
                }
            }
        }
    }
    
    private func setupApp() {
        // Request necessary permissions on first launch
        requestPermissions()
        
        // Register default values for UserDefaults if needed
        registerDefaultValues()
    }
    
    private func requestPermissions() {
        // For macOS, we would typically request file access permissions here
        // This is handled by the system when the user selects folders to scan
    }
    
    private func registerDefaultValues() {
        // Register any default values for UserDefaults if needed
        // This is already handled in the AppPreferences class
    }
    
    private func openPreferences() {
        // Switch to the Settings tab in the main view
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newScan = Notification.Name("NewScan")
    static let stopScan = Notification.Name("StopScan")
    static let saveScan = Notification.Name("SaveScan")
    static let loadScan = Notification.Name("LoadScan")
    static let resetVisualization = Notification.Name("ResetVisualization")
    static let setColorScheme = Notification.Name("SetColorScheme")
    static let analyzeCurrentScan = Notification.Name("AnalyzeCurrentScan")
    static let showSettings = Notification.Name("ShowSettings")
}