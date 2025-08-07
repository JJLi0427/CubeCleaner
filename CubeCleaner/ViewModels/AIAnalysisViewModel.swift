//
//  AIAnalysisViewModel.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import SwiftUI
import Combine

class AIAnalysisViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentScanResult: ScanResult?
    @Published var isAnalyzing: Bool = false
    @Published var analysisResults: [AIAnalysisResult] = []
    @Published var cleanupRecommendation: AICleanupRecommendation?
    @Published var errorMessage: String?
    @Published var isAPIKeyConfigured: Bool = false
    @Published var selectedCategory: String?
    @Published var filteredResults: [AIAnalysisResult] = []
    @Published var selectedItem: AIAnalysisResult?
    
    // MARK: - Private Properties
    
    private let aiService: AIAnalysisServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var appPreferences: AppPreferences
    
    // MARK: - Initialization
    
    init(aiService: AIAnalysisServiceProtocol = AIAnalysisService(), appPreferences: AppPreferences = AppPreferences.shared) {
        self.aiService = aiService
        self.appPreferences = appPreferences
        
        // Check if API key is configured
        self.isAPIKeyConfigured = aiService.isAPIKeyConfigured()
        
        // Set up observers
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    func analyzeScanResult(_ scanResult: ScanResult) async {
        guard isAPIKeyConfigured else {
            DispatchQueue.main.async {
                self.errorMessage = "API key not configured. Please add your OpenAI API key in Settings."
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isAnalyzing = true
            self.errorMessage = nil
            self.currentScanResult = scanResult
            self.analysisResults = []
            self.cleanupRecommendation = nil
        }
        
        do {
            // Analyze scan result
            let results = try await aiService.analyzeScanResult(scanResult)
            
            DispatchQueue.main.async {
                self.analysisResults = results
                self.filterResultsByCategory(self.selectedCategory)
            }
            
            // Get cleanup recommendations
            let recommendation = try await aiService.getCleanupRecommendations(for: scanResult)
            
            DispatchQueue.main.async {
                self.cleanupRecommendation = recommendation
                self.isAnalyzing = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
    
    func analyzeItem(_ item: FileSystemItem) async {
        guard isAPIKeyConfigured else {
            DispatchQueue.main.async {
                self.errorMessage = "API key not configured. Please add your OpenAI API key in Settings."
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isAnalyzing = true
            self.errorMessage = nil
        }
        
        do {
            // Analyze item
            let result = try await aiService.analyzeItem(item)
            
            DispatchQueue.main.async {
                // Add result if not already present
                if !self.analysisResults.contains(where: { $0.itemId == result.itemId }) {
                    self.analysisResults.append(result)
                    self.filterResultsByCategory(self.selectedCategory)
                }
                
                self.selectedItem = result
                self.isAnalyzing = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
    
    func setAPIKey(_ key: String) {
        aiService.setAPIKey(key)
        isAPIKeyConfigured = aiService.isAPIKeyConfigured()
    }
    
    func selectCategory(_ category: String?) {
        self.selectedCategory = category
        filterResultsByCategory(category)
    }
    
    func selectItem(_ item: AIAnalysisResult?) {
        self.selectedItem = item
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // No observers needed for now
    }
    
    private func filterResultsByCategory(_ category: String?) {
        guard let category = category else {
            // If no category selected, show all results
            filteredResults = analysisResults
            return
        }
        
        // Filter results by category
        if category == "All" {
            filteredResults = analysisResults
        } else if let usageCategory = AIAnalysisResult.UsageCategory(rawValue: category) {
            // Filter by usage category
            filteredResults = analysisResults.filter { $0.usageCategory == usageCategory }
        } else if let recommendation = cleanupRecommendation?.recommendations.first(where: { $0.category == category }) {
            // Filter by recommendation category
            // This is a simplified approach - in a real app, you'd need a more sophisticated way to match items to categories
            let unusedCategories: [AIAnalysisResult.UsageCategory] = [.rarely, .unused]
            filteredResults = analysisResults.filter { unusedCategories.contains($0.usageCategory) }
        } else {
            filteredResults = analysisResults
        }
    }
}