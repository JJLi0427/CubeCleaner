//
//  AIAnalysisService.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import Combine

// Protocol defining the AI analysis service interface
protocol AIAnalysisServiceProtocol {
    func analyzeItem(_ item: FileSystemItem) async throws -> AIAnalysisResult
    func analyzeScanResult(_ scanResult: ScanResult) async throws -> [AIAnalysisResult]
    func getCleanupRecommendations(for scanResult: ScanResult) async throws -> AICleanupRecommendation
    func isAPIKeyConfigured() -> Bool
    func setAPIKey(_ key: String)
}

// Represents the result of an AI analysis for a single item
struct AIAnalysisResult: Identifiable, Codable {
    let id: UUID
    let itemId: UUID
    let itemPath: String
    let itemName: String
    let itemSize: Int64
    let itemType: FileType
    let analysisDate: Date
    let usageCategory: UsageCategory
    let confidence: Float
    let recommendation: String
    let reasoning: String
    
    enum UsageCategory: String, Codable, CaseIterable {
        case essential = "Essential"
        case frequently = "Frequently Used"
        case occasionally = "Occasionally Used"
        case rarely = "Rarely Used"
        case unused = "Unused"
        case unknown = "Unknown"
        
        var description: String {
            switch self {
            case .essential:
                return "System or application files that are critical for operation"
            case .frequently:
                return "Files accessed within the last week"
            case .occasionally:
                return "Files accessed within the last month"
            case .rarely:
                return "Files not accessed in over 3 months"
            case .unused:
                return "Files not accessed in over a year or duplicates"
            case .unknown:
                return "Unable to determine usage pattern"
            }
        }
        
        var icon: String {
            switch self {
            case .essential: return "lock.shield"
            case .frequently: return "star.fill"
            case .occasionally: return "star"
            case .rarely: return "clock"
            case .unused: return "trash"
            case .unknown: return "questionmark.circle"
            }
        }
        
        var color: String {
            switch self {
            case .essential: return "#FF2D55" // Red
            case .frequently: return "#30D158" // Green
            case .occasionally: return "#FFD60A" // Yellow
            case .rarely: return "#FF9F0A" // Orange
            case .unused: return "#8E8E93" // Gray
            case .unknown: return "#5E5CE6" // Purple
            }
        }
    }
    
    init(item: FileSystemItem, usageCategory: UsageCategory, confidence: Float, recommendation: String, reasoning: String) {
        self.id = UUID()
        self.itemId = item.id
        self.itemPath = item.url.path
        self.itemName = item.name
        self.itemSize = item.size
        self.itemType = item.type
        self.analysisDate = Date()
        self.usageCategory = usageCategory
        self.confidence = confidence
        self.recommendation = recommendation
        self.reasoning = reasoning
    }
}

// Represents a comprehensive cleanup recommendation for a scan result
struct AICleanupRecommendation: Identifiable, Codable {
    let id: UUID
    let scanResultId: UUID
    let scanPath: String
    let analysisDate: Date
    let totalSize: Int64
    let potentialSavings: Int64
    let recommendations: [CategoryRecommendation]
    let topItems: [AIAnalysisResult]
    
    struct CategoryRecommendation: Identifiable, Codable {
        let id: UUID
        let category: String
        let description: String
        let itemCount: Int
        let totalSize: Int64
        let confidence: Float
        
        init(category: String, description: String, itemCount: Int, totalSize: Int64, confidence: Float) {
            self.id = UUID()
            self.category = category
            self.description = description
            self.itemCount = itemCount
            self.totalSize = totalSize
            self.confidence = confidence
        }
    }
    
    init(scanResult: ScanResult, recommendations: [CategoryRecommendation], topItems: [AIAnalysisResult], potentialSavings: Int64) {
        self.id = UUID()
        self.scanResultId = scanResult.id
        self.scanPath = scanResult.scanPath
        self.analysisDate = Date()
        self.totalSize = scanResult.totalSize
        self.potentialSavings = potentialSavings
        self.recommendations = recommendations
        self.topItems = topItems
    }
}

// Implementation of the AI analysis service using OpenAI API
class AIAnalysisService: AIAnalysisServiceProtocol {
    // MARK: - Private Properties
    
    private var apiKey: String? {
        get { KeychainManager.shared.retrieveAPIKey(for: "openai") }
        set { 
            if let newValue = newValue {
                KeychainManager.shared.storeAPIKey(newValue, for: "openai")
            } else {
                KeychainManager.shared.deleteAPIKey(for: "openai")
            }
        }
    }
    
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4"
    private let cache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - AIAnalysisServiceProtocol Methods
    
    func analyzeItem(_ item: FileSystemItem) async throws -> AIAnalysisResult {
        // Check if API key is configured
        guard isAPIKeyConfigured() else {
            throw AIAnalysisError.apiKeyNotConfigured
        }
        
        // Check cache first
        let cacheKey = NSString(string: "item_\(item.id.uuidString)")
        if let cachedData = cache.object(forKey: cacheKey) as Data?,
           let cachedResult = try? JSONDecoder().decode(AIAnalysisResult.self, from: cachedData) {
            return cachedResult
        }
        
        // Prepare item data for analysis
        let itemData = prepareItemDataForAnalysis(item)
        
        // Create prompt for AI
        let prompt = createAnalysisPrompt(for: item, with: itemData)
        
        // Call OpenAI API
        let response = try await callOpenAI(with: prompt)
        
        // Parse response
        let result = try parseAnalysisResponse(response, for: item)
        
        // Cache result
        if let resultData = try? JSONEncoder().encode(result) {
            cache.setObject(resultData as NSData, forKey: cacheKey)
        }
        
        return result
    }
    
    func analyzeScanResult(_ scanResult: ScanResult) async throws -> [AIAnalysisResult] {
        // Check if API key is configured
        guard isAPIKeyConfigured() else {
            throw AIAnalysisError.apiKeyNotConfigured
        }
        
        var results: [AIAnalysisResult] = []
        
        // Analyze root item
        let rootResult = try await analyzeItem(scanResult.rootItem)
        results.append(rootResult)
        
        // Get largest items for analysis
        let largestItems = scanResult.getLargestItems(count: 10)
        
        // Analyze each large item
        for item in largestItems where item.id != scanResult.rootItem.id {
            let result = try await analyzeItem(item)
            results.append(result)
        }
        
        // Get oldest items for analysis
        let oldestItems = scanResult.getOldestItems(count: 5)
        
        // Analyze each old item
        for item in oldestItems where !results.contains(where: { $0.itemId == item.id }) {
            let result = try await analyzeItem(item)
            results.append(result)
        }
        
        return results
    }
    
    func getCleanupRecommendations(for scanResult: ScanResult) async throws -> AICleanupRecommendation {
        // Check if API key is configured
        guard isAPIKeyConfigured() else {
            throw AIAnalysisError.apiKeyNotConfigured
        }
        
        // Analyze individual items first
        let itemResults = try await analyzeScanResult(scanResult)
        
        // Prepare scan data for analysis
        let scanData = prepareScanDataForAnalysis(scanResult)
        
        // Create prompt for AI
        let prompt = createRecommendationPrompt(for: scanResult, with: scanData, itemResults: itemResults)
        
        // Call OpenAI API
        let response = try await callOpenAI(with: prompt)
        
        // Parse response
        let recommendation = try parseRecommendationResponse(response, for: scanResult, itemResults: itemResults)
        
        return recommendation
    }
    
    func isAPIKeyConfigured() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    func setAPIKey(_ key: String) {
        self.apiKey = key
    }
    
    // MARK: - Private Methods
    
    private func prepareItemDataForAnalysis(_ item: FileSystemItem) -> [String: Any] {
        var itemData: [String: Any] = [
            "name": item.name,
            "path": item.url.path,
            "size": item.formattedSize,
            "type": item.type.rawValue,
            "isDirectory": item.isDirectory,
            "creationDate": item.creationDate?.description ?? "Unknown",
            "modificationDate": item.modificationDate?.description ?? "Unknown",
            "accessDate": item.accessDate?.description ?? "Unknown",
            "ageInDays": item.ageInDays
        ]
        
        // Add additional metadata for specific file types
        if !item.isDirectory {
            // Get file attributes
            if let attributes = try? fileManager.attributesOfItem(atPath: item.url.path) {
                itemData["fileAttributes"] = attributes
            }
            
            // Check if it's a duplicate
            // In a real implementation, this would use a more sophisticated duplicate detection algorithm
            itemData["potentialDuplicate"] = false
        } else if let children = item.children {
            // For directories, include summary of contents
            let fileTypes = Dictionary(grouping: children, by: { $0.type })
                .mapValues { $0.count }
            
            itemData["contentSummary"] = [
                "totalItems": children.count,
                "fileTypes": fileTypes
            ]
        }
        
        return itemData
    }
    
    private func prepareScanDataForAnalysis(_ scanResult: ScanResult) -> [String: Any] {
        // Prepare scan result data for analysis
        var scanData: [String: Any] = [
            "scanPath": scanResult.scanPath,
            "scanDate": scanResult.scanDate.description,
            "totalSize": scanResult.totalSize,
            "formattedTotalSize": FileSystemItem.formatSize(scanResult.totalSize),
            "itemCount": scanResult.itemCount
        ]
        
        // Add file type distribution
        if let rootItem = scanResult.rootItem.children {
            let fileTypeDistribution = Dictionary(grouping: rootItem, by: { $0.type })
                .mapValues { items in
                    let totalSize = items.reduce(0) { $0 + $1.size }
                    return [
                        "count": items.count,
                        "totalSize": totalSize,
                        "formattedTotalSize": FileSystemItem.formatSize(totalSize)
                    ]
                }
            
            scanData["fileTypeDistribution"] = fileTypeDistribution
        }
        
        // Add age distribution
        let ageRanges = [
            "last7Days": 0...7,
            "last30Days": 8...30,
            "last90Days": 31...90,
            "last365Days": 91...365,
            "older": 366...Int.max
        ]
        
        var ageDistribution: [String: [String: Any]] = [:]
        
        func collectAgeDistribution(for item: FileSystemItem) {
            for (rangeName, range) in ageRanges {
                if range.contains(item.ageInDays) {
                    if ageDistribution[rangeName] == nil {
                        ageDistribution[rangeName] = ["count": 0, "totalSize": 0]
                    }
                    
                    ageDistribution[rangeName]!["count"] = (ageDistribution[rangeName]!["count"] as! Int) + 1
                    ageDistribution[rangeName]!["totalSize"] = (ageDistribution[rangeName]!["totalSize"] as! Int64) + item.size
                }
            }
            
            // Recursively process children
            if let children = item.children {
                for child in children {
                    collectAgeDistribution(for: child)
                }
            }
        }
        
        collectAgeDistribution(for: scanResult.rootItem)
        
        // Format size values
        for (rangeName, data) in ageDistribution {
            let totalSize = data["totalSize"] as! Int64
            ageDistribution[rangeName]!["formattedTotalSize"] = FileSystemItem.formatSize(totalSize)
        }
        
        scanData["ageDistribution"] = ageDistribution
        
        return scanData
    }
    
    private func createAnalysisPrompt(for item: FileSystemItem, with itemData: [String: Any]) -> String {
        // Create a prompt for the AI to analyze a single item
        return """
        You are an AI assistant specialized in analyzing file system data to help users clean up their Mac storage.
        
        Please analyze the following file/folder and determine its usage category, provide a recommendation, and explain your reasoning.
        
        File/Folder Information:
        - Name: \(itemData["name"] as? String ?? "")
        - Path: \(itemData["path"] as? String ?? "")
        - Size: \(itemData["size"] as? String ?? "")
        - Type: \(itemData["type"] as? String ?? "")
        - Is Directory: \(itemData["isDirectory"] as? Bool == true ? "Yes" : "No")
        - Creation Date: \(itemData["creationDate"] as? String ?? "Unknown")
        - Modification Date: \(itemData["modificationDate"] as? String ?? "Unknown")
        - Access Date: \(itemData["accessDate"] as? String ?? "Unknown")
        - Age in Days: \(itemData["ageInDays"] as? Int ?? 0)
        
        \(item.isDirectory ? "Directory Contents Summary:\n\(formatContentSummary(itemData["contentSummary"] as? [String: Any] ?? [:]))" : "")
        
        Categorize this item into one of the following usage categories:
        1. Essential - System or application files that are critical for operation
        2. Frequently Used - Files accessed within the last week
        3. Occasionally Used - Files accessed within the last month
        4. Rarely Used - Files not accessed in over 3 months
        5. Unused - Files not accessed in over a year or duplicates
        6. Unknown - Unable to determine usage pattern
        
        Provide your response in the following JSON format:
        {
            "usageCategory": "[category]",
            "confidence": [0.0-1.0],
            "recommendation": "[keep/archive/delete/review]",
            "reasoning": "[detailed explanation]"
        }
        """
    }
    
    private func createRecommendationPrompt(for scanResult: ScanResult, with scanData: [String: Any], itemResults: [AIAnalysisResult]) -> String {
        // Create a prompt for the AI to provide cleanup recommendations
        let itemResultsJSON = try? JSONEncoder().encode(itemResults)
        let itemResultsString = itemResultsJSON != nil ? String(data: itemResultsJSON!, encoding: .utf8) ?? "[]" : "[]"
        
        return """
        You are an AI assistant specialized in analyzing file system data to help users clean up their Mac storage.
        
        Please analyze the following scan result and provide cleanup recommendations to help the user free up disk space.
        
        Scan Information:
        - Scan Path: \(scanData["scanPath"] as? String ?? "")
        - Scan Date: \(scanData["scanDate"] as? String ?? "")
        - Total Size: \(scanData["formattedTotalSize"] as? String ?? "")
        - Item Count: \(scanData["itemCount"] as? Int ?? 0)
        
        File Type Distribution:
        \(formatFileTypeDistribution(scanData["fileTypeDistribution"] as? [FileType: [String: Any]] ?? [:]))
        
        Age Distribution:
        \(formatAgeDistribution(scanData["ageDistribution"] as? [String: [String: Any]] ?? [:]))
        
        Individual Item Analyses:
        \(itemResultsString)
        
        Based on this information, provide cleanup recommendations to help the user free up disk space.
        Group your recommendations into categories (e.g., "Large unused files", "Old backups", "Duplicate media").
        
        For each category, provide:
        1. A descriptive name
        2. A brief explanation
        3. Estimated number of items
        4. Estimated total size
        5. Confidence level (0.0-1.0)
        
        Also provide an estimate of the total potential space savings.
        
        Provide your response in the following JSON format:
        {
            "potentialSavings": [bytes],
            "categories": [
                {
                    "category": "[category name]",
                    "description": "[brief explanation]",
                    "itemCount": [estimated number],
                    "totalSize": [bytes],
                    "confidence": [0.0-1.0]
                },
                ...
            ]
        }
        """
    }
    
    private func formatContentSummary(_ summary: [String: Any]) -> String {
        guard let totalItems = summary["totalItems"] as? Int,
              let fileTypes = summary["fileTypes"] as? [FileType: Int] else {
            return "No content summary available"
        }
        
        var result = "- Total Items: \(totalItems)\n"
        result += "- File Types:\n"
        
        for (type, count) in fileTypes.sorted(by: { $0.value > $1.value }) {
            result += "  - \(type.rawValue): \(count)\n"
        }
        
        return result
    }
    
    private func formatFileTypeDistribution(_ distribution: [FileType: [String: Any]]) -> String {
        var result = ""
        
        for (type, data) in distribution.sorted(by: { ($0.value["totalSize"] as? Int64 ?? 0) > ($1.value["totalSize"] as? Int64 ?? 0) }) {
            let count = data["count"] as? Int ?? 0
            let formattedSize = data["formattedTotalSize"] as? String ?? "Unknown"
            
            result += "- \(type.rawValue): \(count) items, \(formattedSize)\n"
        }
        
        return result.isEmpty ? "No file type distribution available" : result
    }
    
    private func formatAgeDistribution(_ distribution: [String: [String: Any]]) -> String {
        let ageRangeOrder = ["last7Days", "last30Days", "last90Days", "last365Days", "older"]
        let ageRangeNames = [
            "last7Days": "Last 7 Days",
            "last30Days": "Last 30 Days",
            "last90Days": "Last 90 Days",
            "last365Days": "Last 365 Days",
            "older": "Older than 1 Year"
        ]
        
        var result = ""
        
        for rangeName in ageRangeOrder {
            guard let data = distribution[rangeName] else { continue }
            
            let count = data["count"] as? Int ?? 0
            let formattedSize = data["formattedTotalSize"] as? String ?? "Unknown"
            let displayName = ageRangeNames[rangeName] ?? rangeName
            
            result += "- \(displayName): \(count) items, \(formattedSize)\n"
        }
        
        return result.isEmpty ? "No age distribution available" : result
    }
    
    private func callOpenAI(with prompt: String) async throws -> Data {
        guard let apiKey = apiKey else {
            throw AIAnalysisError.apiKeyNotConfigured
        }
        
        // Prepare request
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that analyzes file system data to provide cleanup recommendations."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorResponse["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIAnalysisError.apiError(message)
            } else {
                throw AIAnalysisError.httpError(httpResponse.statusCode)
            }
        }
        
        return data
    }
    
    private func parseAnalysisResponse(_ data: Data, for item: FileSystemItem) throws -> AIAnalysisResult {
        // Parse OpenAI response
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse
        }
        
        // Extract JSON from content
        guard let jsonStartIndex = content.firstIndex(of: "{"),
              let jsonEndIndex = content.lastIndex(of: "}") else {
            throw AIAnalysisError.invalidResponseFormat
        }
        
        let jsonString = String(content[jsonStartIndex...jsonEndIndex])
        
        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIAnalysisError.invalidResponseFormat
        }
        
        // Extract fields
        guard let usageCategoryString = json["usageCategory"] as? String,
              let usageCategory = AIAnalysisResult.UsageCategory(rawValue: usageCategoryString) ?? AIAnalysisResult.UsageCategory(rawValue: usageCategoryString.capitalized),
              let confidence = json["confidence"] as? Double,
              let recommendation = json["recommendation"] as? String,
              let reasoning = json["reasoning"] as? String else {
            throw AIAnalysisError.missingRequiredFields
        }
        
        // Create result
        return AIAnalysisResult(
            item: item,
            usageCategory: usageCategory,
            confidence: Float(confidence),
            recommendation: recommendation,
            reasoning: reasoning
        )
    }
    
    private func parseRecommendationResponse(_ data: Data, for scanResult: ScanResult, itemResults: [AIAnalysisResult]) throws -> AICleanupRecommendation {
        // Parse OpenAI response
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse
        }
        
        // Extract JSON from content
        guard let jsonStartIndex = content.firstIndex(of: "{"),
              let jsonEndIndex = content.lastIndex(of: "}") else {
            throw AIAnalysisError.invalidResponseFormat
        }
        
        let jsonString = String(content[jsonStartIndex...jsonEndIndex])
        
        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIAnalysisError.invalidResponseFormat
        }
        
        // Extract fields
        guard let potentialSavings = json["potentialSavings"] as? Int64,
              let categories = json["categories"] as? [[String: Any]] else {
            throw AIAnalysisError.missingRequiredFields
        }
        
        // Create category recommendations
        var categoryRecommendations: [AICleanupRecommendation.CategoryRecommendation] = []
        
        for category in categories {
            guard let name = category["category"] as? String,
                  let description = category["description"] as? String,
                  let itemCount = category["itemCount"] as? Int,
                  let totalSize = category["totalSize"] as? Int64,
                  let confidence = category["confidence"] as? Double else {
                continue
            }
            
            categoryRecommendations.append(AICleanupRecommendation.CategoryRecommendation(
                category: name,
                description: description,
                itemCount: itemCount,
                totalSize: totalSize,
                confidence: Float(confidence)
            ))
        }
        
        // Sort item results by size (largest first)
        let sortedItems = itemResults.sorted { $0.itemSize > $1.itemSize }
        
        // Create cleanup recommendation
        return AICleanupRecommendation(
            scanResult: scanResult,
            recommendations: categoryRecommendations,
            topItems: Array(sortedItems.prefix(10)),
            potentialSavings: potentialSavings
        )
    }
}

// MARK: - Errors

enum AIAnalysisError: Error, LocalizedError {
    case apiKeyNotConfigured
    case invalidResponse
    case invalidResponseFormat
    case missingRequiredFields
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "API key not configured. Please add your OpenAI API key in Settings."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .invalidResponseFormat:
            return "Invalid response format from AI service."
        case .missingRequiredFields:
            return "Missing required fields in AI response."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

// MARK: - KeychainManager

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    func storeAPIKey(_ key: String, for service: String) {
        // In a real implementation, this would use the Keychain API to securely store the API key
        // For this example, we'll use UserDefaults, but this is NOT secure for real API keys
        UserDefaults.standard.set(key, forKey: "APIKey_\(service)")
    }
    
    func retrieveAPIKey(for service: String) -> String? {
        // In a real implementation, this would use the Keychain API to securely retrieve the API key
        // For this example, we'll use UserDefaults, but this is NOT secure for real API keys
        return UserDefaults.standard.string(forKey: "APIKey_\(service)")
    }
    
    func deleteAPIKey(for service: String) {
        // In a real implementation, this would use the Keychain API to securely delete the API key
        // For this example, we'll use UserDefaults
        UserDefaults.standard.removeObject(forKey: "APIKey_\(service)")
    }
}