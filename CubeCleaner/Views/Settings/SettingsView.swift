//
//  SettingsView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var showResetConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Appearance settings
                appearanceSettings
                
                Divider()
                
                // Visualization settings
                visualizationSettings
                
                Divider()
                
                // Scan settings
                scanSettings
                
                Divider()
                
                // AI settings
                aiSettings
                
                Divider()
                
                // Advanced settings
                advancedSettings
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Reset All Settings", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                preferences.resetToDefaults()
            }
        } message: {
            Text("Are you sure you want to reset all settings to their default values? This action cannot be undone.")
        }
    }
    
    // MARK: - Appearance Settings
    
    private var appearanceSettings: some View {
        GroupBox(label: Label("Appearance", systemImage: "paintpalette")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Color Theme", selection: $preferences.colorTheme) {
                    Text("System").tag(ColorTheme.system)
                    Text("Light").tag(ColorTheme.light)
                    Text("Dark").tag(ColorTheme.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("Use Animations", isOn: $preferences.useAnimations)
                    .help("Enable or disable animations throughout the app")
                
                Toggle("Show File Icons", isOn: $preferences.showFileIcons)
                    .help("Show file type icons in lists and visualizations")
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Visualization Settings
    
    private var visualizationSettings: some View {
        GroupBox(label: Label("Visualization", systemImage: "cube")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Default Color Scheme", selection: $preferences.defaultColorScheme) {
                    ForEach(ColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                
                Picker("Default Visualization Mode", selection: $preferences.defaultVisualizationMode) {
                    ForEach(VisualizationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                
                Toggle("Show Hidden Files", isOn: $preferences.showHiddenFiles)
                    .help("Show hidden files and folders in visualizations")
                
                Toggle("Show Package Contents", isOn: $preferences.showPackageContents)
                    .help("Show the contents of packages like .app files")
                
                Slider(value: $preferences.cubeSpacing, in: 0...5, step: 0.5) {
                    Text("Cube Spacing: \(preferences.cubeSpacing, specifier: "%.1f")")
                }
                .help("Adjust the spacing between cubes in the visualization")
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Scan Settings
    
    private var scanSettings: some View {
        GroupBox(label: Label("Scanning", systemImage: "doc.viewfinder")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Exclude Hidden Files by Default", isOn: $preferences.excludeHiddenFilesByDefault)
                    .help("Automatically exclude hidden files and folders when scanning")
                
                Toggle("Exclude System Files by Default", isOn: $preferences.excludeSystemFilesByDefault)
                    .help("Automatically exclude system files and folders when scanning")
                
                Picker("Maximum Scan Depth", selection: Binding(
                    get: { preferences.defaultMaxScanDepth == nil ? 0 : preferences.defaultMaxScanDepth! },
                    set: { preferences.defaultMaxScanDepth = $0 == 0 ? nil : $0 }
                )) {
                    Text("No Limit").tag(0)
                    ForEach(1...10, id: \.self) { depth in
                        Text("\(depth) levels").tag(depth)
                    }
                }
                .help("Set the default maximum folder depth for scans")
                
                Toggle("Scan Package Contents by Default", isOn: $preferences.scanPackageContentsByDefault)
                    .help("Automatically scan inside package files like .app")
                
                Picker("Recent Scans to Keep", selection: $preferences.recentScansToKeep) {
                    ForEach([5, 10, 20, 50], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .help("Number of recent scans to keep in history")
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - AI Settings
    
    private var aiSettings: some View {
        GroupBox(label: Label("AI Analysis", systemImage: "brain")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use AI Analysis", isOn: $preferences.useAIAnalysis)
                    .help("Enable or disable AI analysis features")
                
                Picker("AI Model", selection: $preferences.aiModel) {
                    ForEach(AIModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .disabled(!preferences.useAIAnalysis)
                .help("Select which AI model to use for analysis")
                
                Button("Configure API Key") {
                    NotificationCenter.default.post(name: .showAPIKeyConfig, object: nil)
                }
                .disabled(!preferences.useAIAnalysis)
                .help("Configure your OpenAI API key")
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Advanced Settings
    
    private var advancedSettings: some View {
        GroupBox(label: Label("Advanced", systemImage: "gearshape.2")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Debug Logging", isOn: $preferences.enableDebugLogging)
                    .help("Enable detailed logging for troubleshooting")
                
                Picker("Cache Size", selection: $preferences.cacheSize) {
                    Text("Small (50 MB)").tag(50)
                    Text("Medium (100 MB)").tag(100)
                    Text("Large (250 MB)").tag(250)
                    Text("Extra Large (500 MB)").tag(500)
                }
                .help("Set the maximum size for the app's cache")
                
                Button("Clear Cache") {
                    preferences.clearCache()
                }
                .help("Clear all cached data")
                
                Button("Reset All Settings") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
                .help("Reset all settings to their default values")
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showAPIKeyConfig = Notification.Name("ShowAPIKeyConfig")
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(preferences: AppPreferences.shared)
    }
}