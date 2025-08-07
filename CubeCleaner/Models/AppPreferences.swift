//
//  AppPreferences.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI
import Combine

// MARK: - Enums for Preferences

enum ColorTheme: String, CaseIterable, Codable {
    case system
    case light
    case dark
}

enum ColorScheme: String, CaseIterable, Codable {
    case fileType
    case modificationDate
    case size
    case parentFolder
    case fileExtension
    case depth
    
    var displayName: String {
        switch self {
        case .fileType: return "File Type"
        case .modificationDate: return "Modification Date"
        case .size: return "File Size"
        case .parentFolder: return "Parent Folder"
        case .fileExtension: return "File Extension"
        case .depth: return "Directory Depth"
        }
    }
}

enum VisualizationMode: String, CaseIterable, Codable {
    case treemap
    case cubes
    case sunburst
    
    var displayName: String {
        switch self {
        case .treemap: return "Treemap"
        case .cubes: return "3D Cubes"
        case .sunburst: return "Sunburst"
        }
    }
}

enum AIModel: String, CaseIterable, Codable {
    case gpt35Turbo
    case gpt4
    
    var displayName: String {
        switch self {
        case .gpt35Turbo: return "GPT-3.5 Turbo"
        case .gpt4: return "GPT-4"
        }
    }
    
    var modelIdentifier: String {
        switch self {
        case .gpt35Turbo: return "gpt-3.5-turbo"
        case .gpt4: return "gpt-4"
        }
    }
}

// MARK: - AppPreferences Class

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Appearance
    
    @Published var colorTheme: ColorTheme {
        didSet {
            userDefaults.set(colorTheme.rawValue, forKey: Keys.colorTheme)
            updateAppAppearance()
        }
    }
    
    @Published var useAnimations: Bool {
        didSet { userDefaults.set(useAnimations, forKey: Keys.useAnimations) }
    }
    
    @Published var showFileIcons: Bool {
        didSet { userDefaults.set(showFileIcons, forKey: Keys.showFileIcons) }
    }
    
    // MARK: - Visualization
    
    @Published var defaultColorScheme: ColorScheme {
        didSet { userDefaults.set(defaultColorScheme.rawValue, forKey: Keys.defaultColorScheme) }
    }
    
    @Published var defaultVisualizationMode: VisualizationMode {
        didSet { userDefaults.set(defaultVisualizationMode.rawValue, forKey: Keys.defaultVisualizationMode) }
    }
    
    @Published var showHiddenFiles: Bool {
        didSet { userDefaults.set(showHiddenFiles, forKey: Keys.showHiddenFiles) }
    }
    
    @Published var showPackageContents: Bool {
        didSet { userDefaults.set(showPackageContents, forKey: Keys.showPackageContents) }
    }
    
    @Published var cubeSpacing: Double {
        didSet { userDefaults.set(cubeSpacing, forKey: Keys.cubeSpacing) }
    }
    
    // MARK: - Scanning
    
    @Published var excludeHiddenFilesByDefault: Bool {
        didSet { userDefaults.set(excludeHiddenFilesByDefault, forKey: Keys.excludeHiddenFilesByDefault) }
    }
    
    @Published var excludeSystemFilesByDefault: Bool {
        didSet { userDefaults.set(excludeSystemFilesByDefault, forKey: Keys.excludeSystemFilesByDefault) }
    }
    
    @Published var defaultMaxScanDepth: Int? {
        didSet {
            if let depth = defaultMaxScanDepth {
                userDefaults.set(depth, forKey: Keys.defaultMaxScanDepth)
            } else {
                userDefaults.removeObject(forKey: Keys.defaultMaxScanDepth)
            }
        }
    }
    
    @Published var scanPackageContentsByDefault: Bool {
        didSet { userDefaults.set(scanPackageContentsByDefault, forKey: Keys.scanPackageContentsByDefault) }
    }
    
    @Published var recentScansToKeep: Int {
        didSet { userDefaults.set(recentScansToKeep, forKey: Keys.recentScansToKeep) }
    }
    
    // MARK: - AI Analysis
    
    @Published var useAIAnalysis: Bool {
        didSet { userDefaults.set(useAIAnalysis, forKey: Keys.useAIAnalysis) }
    }
    
    @Published var aiModel: AIModel {
        didSet { userDefaults.set(aiModel.rawValue, forKey: Keys.aiModel) }
    }
    
    // MARK: - Advanced
    
    @Published var enableDebugLogging: Bool {
        didSet { userDefaults.set(enableDebugLogging, forKey: Keys.enableDebugLogging) }
    }
    
    @Published var cacheSize: Int {
        didSet { userDefaults.set(cacheSize, forKey: Keys.cacheSize) }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load values from UserDefaults or use defaults
        self.colorTheme = ColorTheme(rawValue: userDefaults.string(forKey: Keys.colorTheme) ?? "") ?? .system
        self.useAnimations = userDefaults.bool(forKey: Keys.useAnimations, defaultValue: true)
        self.showFileIcons = userDefaults.bool(forKey: Keys.showFileIcons, defaultValue: true)
        
        self.defaultColorScheme = ColorScheme(rawValue: userDefaults.string(forKey: Keys.defaultColorScheme) ?? "") ?? .fileType
        self.defaultVisualizationMode = VisualizationMode(rawValue: userDefaults.string(forKey: Keys.defaultVisualizationMode) ?? "") ?? .cubes
        self.showHiddenFiles = userDefaults.bool(forKey: Keys.showHiddenFiles, defaultValue: false)
        self.showPackageContents = userDefaults.bool(forKey: Keys.showPackageContents, defaultValue: false)
        self.cubeSpacing = userDefaults.double(forKey: Keys.cubeSpacing, defaultValue: 1.0)
        
        self.excludeHiddenFilesByDefault = userDefaults.bool(forKey: Keys.excludeHiddenFilesByDefault, defaultValue: true)
        self.excludeSystemFilesByDefault = userDefaults.bool(forKey: Keys.excludeSystemFilesByDefault, defaultValue: true)
        self.defaultMaxScanDepth = userDefaults.object(forKey: Keys.defaultMaxScanDepth) as? Int
        self.scanPackageContentsByDefault = userDefaults.bool(forKey: Keys.scanPackageContentsByDefault, defaultValue: false)
        self.recentScansToKeep = userDefaults.integer(forKey: Keys.recentScansToKeep, defaultValue: 10)
        
        self.useAIAnalysis = userDefaults.bool(forKey: Keys.useAIAnalysis, defaultValue: true)
        self.aiModel = AIModel(rawValue: userDefaults.string(forKey: Keys.aiModel) ?? "") ?? .gpt35Turbo
        
        self.enableDebugLogging = userDefaults.bool(forKey: Keys.enableDebugLogging, defaultValue: false)
        self.cacheSize = userDefaults.integer(forKey: Keys.cacheSize, defaultValue: 100)
        
        // Apply initial appearance
        updateAppAppearance()
    }
    
    // MARK: - Methods
    
    func resetToDefaults() {
        // Reset all preferences to default values
        self.colorTheme = .system
        self.useAnimations = true
        self.showFileIcons = true
        
        self.defaultColorScheme = .fileType
        self.defaultVisualizationMode = .cubes
        self.showHiddenFiles = false
        self.showPackageContents = false
        self.cubeSpacing = 1.0
        
        self.excludeHiddenFilesByDefault = true
        self.excludeSystemFilesByDefault = true
        self.defaultMaxScanDepth = nil
        self.scanPackageContentsByDefault = false
        self.recentScansToKeep = 10
        
        self.useAIAnalysis = true
        self.aiModel = .gpt35Turbo
        
        self.enableDebugLogging = false
        self.cacheSize = 100
    }
    
    func clearCache() {
        // Implementation for clearing the app's cache
        // This would typically involve deleting files from the app's cache directory
        let fileManager = FileManager.default
        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            do {
                let cacheContents = try fileManager.contentsOfDirectory(at: cachesDirectory, includingPropertiesForKeys: nil)
                for fileURL in cacheContents {
                    try fileManager.removeItem(at: fileURL)
                }
                print("Cache cleared successfully")
            } catch {
                print("Failed to clear cache: \(error)")
            }
        }
    }
    
    private func updateAppAppearance() {
        // Update the app's appearance based on the selected theme
        DispatchQueue.main.async {
            let appearance = NSAppearance.Name.aqua
            switch self.colorTheme {
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            case .system:
                NSApp.appearance = nil
            }
        }
    }
    
    // MARK: - Default Scan Parameters
    
    func getDefaultScanParameters() -> ScanParameters {
        return ScanParameters(
            excludeHiddenFiles: excludeHiddenFilesByDefault,
            excludeSystemFiles: excludeSystemFilesByDefault,
            maxDepth: defaultMaxScanDepth,
            scanPackageContents: scanPackageContentsByDefault,
            excludedPaths: []
        )
    }
}

// MARK: - UserDefaults Keys

extension AppPreferences {
    private struct Keys {
        // Appearance
        static let colorTheme = "colorTheme"
        static let useAnimations = "useAnimations"
        static let showFileIcons = "showFileIcons"
        
        // Visualization
        static let defaultColorScheme = "defaultColorScheme"
        static let defaultVisualizationMode = "defaultVisualizationMode"
        static let showHiddenFiles = "showHiddenFiles"
        static let showPackageContents = "showPackageContents"
        static let cubeSpacing = "cubeSpacing"
        
        // Scanning
        static let excludeHiddenFilesByDefault = "excludeHiddenFilesByDefault"
        static let excludeSystemFilesByDefault = "excludeSystemFilesByDefault"
        static let defaultMaxScanDepth = "defaultMaxScanDepth"
        static let scanPackageContentsByDefault = "scanPackageContentsByDefault"
        static let recentScansToKeep = "recentScansToKeep"
        
        // AI Analysis
        static let useAIAnalysis = "useAIAnalysis"
        static let aiModel = "aiModel"
        
        // Advanced
        static let enableDebugLogging = "enableDebugLogging"
        static let cacheSize = "cacheSize"
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
    
    func integer(forKey key: String, defaultValue: Int) -> Int {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return integer(forKey: key)
    }
    
    func double(forKey key: String, defaultValue: Double) -> Double {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return double(forKey: key)
    }
}

// MARK: - ScanParameters Structure

struct ScanParameters: Codable, Equatable {
    var excludeHiddenFiles: Bool
    var excludeSystemFiles: Bool
    var maxDepth: Int?
    var scanPackageContents: Bool
    var excludedPaths: [String]
    
    init(
        excludeHiddenFiles: Bool = true,
        excludeSystemFiles: Bool = true,
        maxDepth: Int? = nil,
        scanPackageContents: Bool = false,
        excludedPaths: [String] = []
    ) {
        self.excludeHiddenFiles = excludeHiddenFiles
        self.excludeSystemFiles = excludeSystemFiles
        self.maxDepth = maxDepth
        self.scanPackageContents = scanPackageContents
        self.excludedPaths = excludedPaths
    }
}