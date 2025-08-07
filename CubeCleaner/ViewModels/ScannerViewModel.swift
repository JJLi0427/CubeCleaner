//
//  ScannerViewModel.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import SwiftUI
import Combine

class ScannerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isScanning: Bool = false
    @Published var scanProgress: Float = 0.0
    @Published var currentScanPath: String = ""
    @Published var scanResults: [ScanResult] = []
    @Published var currentScanResult: ScanResult?
    @Published var errorMessage: String?
    @Published var scanParameters: ScanParameters = ScanParameters()
    @Published var recentScans: [ScanResult] = []
    
    // MARK: - Private Properties
    
    private let scanner: FileSystemScannerProtocol
    private var scanTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var appPreferences: AppPreferences
    
    // MARK: - Initialization
    
    init(scanner: FileSystemScannerProtocol = FileSystemScanner(), appPreferences: AppPreferences = AppPreferences.shared) {
        self.scanner = scanner
        self.appPreferences = appPreferences
        
        // Load recent scans from preferences
        self.recentScans = appPreferences.recentScans
        
        // Set up default scan parameters from preferences
        self.scanParameters.excludedPaths = appPreferences.scanExcludedPaths
        self.scanParameters.excludeHiddenFiles = appPreferences.excludeHiddenFiles
        self.scanParameters.excludeSystemFiles = appPreferences.excludeSystemFiles
        
        // Set up observers
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    func startScan(path: URL) {
        // Cancel any ongoing scan
        cancelScan()
        
        // Reset state
        isScanning = true
        scanProgress = 0.0
        currentScanPath = path.path
        errorMessage = nil
        
        // Start new scan task
        scanTask = Task {
            do {
                // Create progress handler
                let progressHandler: (Float, String) -> Void = { [weak self] progress, currentPath in
                    guard let self = self else { return }
                    
                    // Update progress on main thread
                    DispatchQueue.main.async {
                        self.scanProgress = progress
                        self.currentScanPath = currentPath
                    }
                }
                
                // Start scan
                let result = try await scanner.scanDirectory(
                    at: path,
                    excludedPaths: scanParameters.excludedPaths,
                    maxDepth: scanParameters.maxDepth,
                    excludeHiddenFiles: scanParameters.excludeHiddenFiles,
                    excludeSystemFiles: scanParameters.excludeSystemFiles,
                    progressHandler: progressHandler
                )
                
                // Update state on main thread
                await MainActor.run {
                    self.currentScanResult = result
                    self.scanResults.append(result)
                    self.isScanning = false
                    
                    // Add to recent scans
                    self.addToRecentScans(result)
                }
            } catch let error as ScannerError {
                // Handle scanner errors
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isScanning = false
                }
            } catch {
                // Handle other errors
                await MainActor.run {
                    self.errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                    self.isScanning = false
                }
            }
        }
    }
    
    func cancelScan() {
        // Cancel ongoing scan task
        scanTask?.cancel()
        scanTask = nil
        
        // Cancel scanner
        scanner.cancelScan()
        
        // Update state
        isScanning = false
    }
    
    func loadScanResult(_ result: ScanResult) {
        self.currentScanResult = result
        
        // Add to recent scans if not already present
        if !recentScans.contains(where: { $0.id == result.id }) {
            addToRecentScans(result)
        }
    }
    
    func quickSizeCheck(at path: URL) async -> Int64? {
        do {
            return try await scanner.quickDirectorySize(at: path)
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to check size: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    func updateScanParameters(_ parameters: ScanParameters) {
        self.scanParameters = parameters
        
        // Update preferences
        appPreferences.scanExcludedPaths = parameters.excludedPaths
        appPreferences.excludeHiddenFiles = parameters.excludeHiddenFiles
        appPreferences.excludeSystemFiles = parameters.excludeSystemFiles
    }
    
    func clearRecentScans() {
        recentScans = []
        appPreferences.recentScans = []
    }
    
    func removeRecentScan(_ scan: ScanResult) {
        recentScans.removeAll { $0.id == scan.id }
        appPreferences.recentScans = recentScans
    }
    
    func saveScanResult(_ result: ScanResult, to url: URL) async -> Bool {
        do {
            // Encode scan result to JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(result)
            
            // Write to file
            try data.write(to: url)
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save scan result: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    func loadScanResultFromFile(at url: URL) async -> ScanResult? {
        do {
            // Read data from file
            let data = try Data(contentsOf: url)
            
            // Decode scan result
            let decoder = JSONDecoder()
            let result = try decoder.decode(ScanResult.self, from: data)
            
            // Update current scan result
            await MainActor.run {
                self.currentScanResult = result
                self.addToRecentScans(result)
            }
            
            return result
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load scan result: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    func compareScanResults(_ result1: ScanResult, _ result2: ScanResult) -> ScanResult.ScanDifference {
        return result1.compareWith(result2)
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // No observers needed for now
    }
    
    private func addToRecentScans(_ result: ScanResult) {
        // Add to recent scans, removing duplicates
        recentScans.removeAll { $0.id == result.id }
        recentScans.insert(result, at: 0)
        
        // Limit to 10 recent scans
        if recentScans.count > 10 {
            recentScans = Array(recentScans.prefix(10))
        }
        
        // Update preferences
        appPreferences.recentScans = recentScans
    }
}

// MARK: - Scan Parameters

struct ScanParameters {
    var excludedPaths: [String] = []
    var maxDepth: Int? = nil
    var excludeHiddenFiles: Bool = true
    var excludeSystemFiles: Bool = true
}