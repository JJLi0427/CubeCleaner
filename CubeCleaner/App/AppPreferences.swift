//
//  AppPreferences.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import SwiftUI

// Enum for visualization color schemes
enum ColorScheme: String, CaseIterable, Identifiable {
    case fileType = "fileType"
    case modificationDate = "modificationDate"
    case size = "size"
    case parentFolder = "parentFolder"
    case custom = "custom"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .fileType: return "File Type"
        case .modificationDate: return "Modification Date"
        case .size: return "File Size"
        case .parentFolder: return "Parent Folder"
        case .custom: return "Custom"
        }
    }
}

// Enum for visualization modes
enum VisualizationMode: String, CaseIterable, Identifiable {
    case cube = "cube"
    case treemap = "treemap"
    case list = "list"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .cube: return "3D Cube"
        case .treemap: return "Treemap"
        case .list: return "List"
        }
    }
}

// Class to manage app preferences
class AppPreferences: ObservableObject {
    // Appearance
    @AppStorage("appTheme") var appTheme: String = "system"
    
    // Visualization
    @AppStorage("defaultVisualizationMode") var defaultVisualizationMode: String = VisualizationMode.cube.rawValue
    @AppStorage("defaultColorScheme") var defaultColorScheme: String = ColorScheme.fileType.rawValue
    @AppStorage("showFileExtensions") var showFileExtensions: Bool = true
    @AppStorage("animateTransitions") var animateTransitions: Bool = true
    
    // Scanning
    @AppStorage("excludeSystemFiles") var excludeSystemFiles: Bool = true
    @AppStorage("excludeHiddenFiles") var excludeHiddenFiles: Bool = true
    @AppStorage("defaultScanDepth") var defaultScanDepth: Int = 0 // 0 means unlimited
    
    // File Operations
    @AppStorage("confirmDeletions") var confirmDeletions: Bool = true
    @AppStorage("moveToTrashByDefault") var moveToTrashByDefault: Bool = true
    
    // AI Integration
    @AppStorage("enableAI") var enableAI: Bool = true
    @AppStorage("aiConfidenceThreshold") var aiConfidenceThreshold: Double = 0.7
    
    // Recent Scans
    @Published var recentScans: [URL] = []
    private let recentScansKey = "recentScans"
    private let maxRecentScans = 10
    
    // Custom File Type Colors
    @Published var fileTypeColors: [String: Color] = [:]
    private let fileTypeColorsKey = "fileTypeColors"
    
    init() {
        loadRecentScans()
        loadFileTypeColors()
    }
    
    // MARK: - Recent Scans Management
    
    func addRecentScan(_ url: URL) {
        // Remove if already exists
        recentScans.removeAll { $0.path == url.path }
        
        // Add to the beginning
        recentScans.insert(url, at: 0)
        
        // Limit the number of recent scans
        if recentScans.count > maxRecentScans {
            recentScans = Array(recentScans.prefix(maxRecentScans))
        }
        
        saveRecentScans()
    }
    
    func clearRecentScans() {
        recentScans.removeAll()
        saveRecentScans()
    }
    
    private func saveRecentScans() {
        if let data = try? JSONEncoder().encode(recentScans.map { $0.path }) {
            UserDefaults.standard.set(data, forKey: recentScansKey)
        }
    }
    
    private func loadRecentScans() {
        guard let data = UserDefaults.standard.data(forKey: recentScansKey),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        
        recentScans = paths.compactMap { URL(fileURLWithPath: $0) }
    }
    
    // MARK: - File Type Colors Management
    
    func setColor(_ color: Color, forFileType fileType: String) {
        fileTypeColors[fileType] = color
        saveFileTypeColors()
    }
    
    func getColor(forFileType fileType: String) -> Color? {
        return fileTypeColors[fileType]
    }
    
    func resetFileTypeColors() {
        fileTypeColors = [:]
        saveFileTypeColors()
    }
    
    private func saveFileTypeColors() {
        // Convert Color to hex string for storage
        let colorDict = fileTypeColors.mapValues { color -> String in
            // This is a placeholder - in a real app, you'd convert Color to a storable format
            return "#FFFFFF" // Placeholder
        }
        
        if let data = try? JSONEncoder().encode(colorDict) {
            UserDefaults.standard.set(data, forKey: fileTypeColorsKey)
        }
    }
    
    private func loadFileTypeColors() {
        guard let data = UserDefaults.standard.data(forKey: fileTypeColorsKey),
              let colorDict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        
        // Convert hex string back to Color
        // This is a placeholder - in a real app, you'd convert from your storage format back to Color
        fileTypeColors = colorDict.mapValues { _ in Color.blue }
    }
    
    // MARK: - API Key Management
    
    func saveAPIKey(_ apiKey: String) {
        // In a real app, you'd use the Keychain for secure storage
        // This is just a placeholder implementation
        UserDefaults.standard.set(apiKey, forKey: "apiKey")
    }
    
    func getAPIKey() -> String? {
        // In a real app, you'd retrieve from the Keychain
        return UserDefaults.standard.string(forKey: "apiKey")
    }
    
    func clearAPIKey() {
        // In a real app, you'd remove from the Keychain
        UserDefaults.standard.removeObject(forKey: "apiKey")
    }
}

// Extension to provide default colors for common file types
extension AppPreferences {
    static let defaultFileTypeColors: [String: Color] = [
        "folder": .blue,
        "txt": .green,
        "pdf": .red,
        "doc": .blue,
        "docx": .blue,
        "xls": .green,
        "xlsx": .green,
        "ppt": .orange,
        "pptx": .orange,
        "jpg": .purple,
        "jpeg": .purple,
        "png": .purple,
        "gif": .purple,
        "mp3": .pink,
        "mp4": .pink,
        "mov": .pink,
        "zip": .yellow,
        "app": .gray,
        "dmg": .gray,
        "exe": .gray,
    ]
    
    func getDefaultColor(forFileType fileType: String) -> Color {
        if let customColor = fileTypeColors[fileType] {
            return customColor
        }
        
        if let defaultColor = AppPreferences.defaultFileTypeColors[fileType.lowercased()] {
            return defaultColor
        }
        
        // Default color for unknown file types
        return .gray
    }
}