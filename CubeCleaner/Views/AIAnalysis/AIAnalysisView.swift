//
//  AIAnalysisView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct AIAnalysisView: View {
    @ObservedObject var viewModel: AIAnalysisViewModel
    @State private var selectedCategory: String? = "All"
    @State private var showAPIKeySheet = false
    
    private let categories = ["All", "Unused", "Rarely Used", "Duplicates", "Large Files", "Temporary Files"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls
            controlsView
                .padding()
                .background(Color.secondary.opacity(0.1))
            
            // Content
            if viewModel.isAnalyzing {
                analysisProgressView
                    .transition(.opacity)
            } else if let analysisResult = viewModel.currentAnalysisResult {
                analysisResultView(for: analysisResult)
                    .transition(.opacity)
            } else if viewModel.apiKeyMissing {
                apiKeyMissingView
                    .transition(.opacity)
            } else {
                emptyAnalysisView
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showAPIKeySheet) {
            APIKeyConfigView(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        HStack {
            Button(action: {
                viewModel.analyzeCurrentScan()
            }) {
                Label("Analyze", systemImage: "brain")
            }
            .disabled(viewModel.currentScanResult == nil || viewModel.isAnalyzing || viewModel.apiKeyMissing)
            
            Button(action: {
                showAPIKeySheet = true
            }) {
                Label("API Key", systemImage: "key")
            }
            
            Spacer()
            
            if viewModel.currentAnalysisResult != nil {
                Menu {
                    ForEach(categories, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            Label(category, systemImage: categoryIcon(for: category))
                        }
                    }
                } label: {
                    Label(selectedCategory ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
    
    // MARK: - Analysis Progress View
    
    private var analysisProgressView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Analyzing Files...")
                .font(.headline)
            
            if let currentItem = viewModel.currentAnalyzingItem {
                Text("Analyzing: \(currentItem.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Cancel") {
                viewModel.cancelAnalysis()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Analysis Result View
    
    private func analysisResultView(for result: AIAnalysisResult) -> some View {
        let filteredRecommendations = filterRecommendations(result.recommendations)
        
        return VStack(spacing: 0) {
            // Summary
            GroupBox(label: Label("Analysis Summary", systemImage: "chart.pie")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.summary)
                        .lineLimit(3)
                        .padding(.bottom, 4)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Potential Space Savings:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(FileSystemItem.formatSize(result.potentialSpaceSavings))
                                .font(.title3)
                                .bold()
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("Recommendations:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(result.recommendations.count)")
                                .font(.title3)
                                .bold()
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("Analysis Date:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(result.analysisDate, format: .dateTime)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .padding()
            
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories, id: \.self) { category in
                        CategoryButton(title: category, 
                                      icon: categoryIcon(for: category), 
                                      isSelected: selectedCategory == category,
                                      count: countForCategory(category, in: result.recommendations)) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color.secondary.opacity(0.05))
            
            // Recommendations list
            List {
                ForEach(filteredRecommendations) { recommendation in
                    RecommendationRow(recommendation: recommendation) {
                        viewModel.selectItem(recommendation.item)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
    }
    
    // MARK: - API Key Missing View
    
    private var apiKeyMissingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "key.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("API Key Required")
                .font(.title2)
            
            Text("To use AI analysis features, you need to configure an OpenAI API key.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Configure API Key") {
                showAPIKeySheet = true
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Empty Analysis View
    
    private var emptyAnalysisView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Analysis Results")
                .font(.title2)
            
            Text("Run a scan first, then analyze it to get AI-powered recommendations.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if viewModel.currentScanResult != nil {
                Button("Analyze Current Scan") {
                    viewModel.analyzeCurrentScan()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    
    private func categoryIcon(for category: String) -> String {
        switch category {
        case "All": return "square.grid.2x2"
        case "Unused": return "xmark.circle"
        case "Rarely Used": return "clock"
        case "Duplicates": return "doc.on.doc"
        case "Large Files": return "arrow.up.forward.app"
        case "Temporary Files": return "trash"
        default: return "questionmark.circle"
        }
    }
    
    private func filterRecommendations(_ recommendations: [AICleanupRecommendation]) -> [AICleanupRecommendation] {
        guard let category = selectedCategory, category != "All" else {
            return recommendations
        }
        
        return recommendations.filter { $0.category == category }
    }
    
    private func countForCategory(_ category: String, in recommendations: [AICleanupRecommendation]) -> Int {
        if category == "All" {
            return recommendations.count
        }
        return recommendations.filter { $0.category == category }.count
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recommendation Row

struct RecommendationRow: View {
    let recommendation: AICleanupRecommendation
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: recommendation.item.type.systemImageName)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .foregroundColor(categoryColor(for: recommendation.category))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.item.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(recommendation.item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(recommendation.item.formattedSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(recommendation.reason)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(3)
            
            HStack {
                Label(recommendation.category, systemImage: categoryIcon(for: recommendation.category))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor(for: recommendation.category).opacity(0.1))
                    .foregroundColor(categoryColor(for: recommendation.category))
                    .cornerRadius(4)
                
                Spacer()
                
                Button("Show in Visualization") {
                    onSelect()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category {
        case "Unused": return "xmark.circle"
        case "Rarely Used": return "clock"
        case "Duplicates": return "doc.on.doc"
        case "Large Files": return "arrow.up.forward.app"
        case "Temporary Files": return "trash"
        default: return "questionmark.circle"
        }
    }
    
    private func categoryColor(for category: String) -> Color {
        switch category {
        case "Unused": return .red
        case "Rarely Used": return .orange
        case "Duplicates": return .blue
        case "Large Files": return .purple
        case "Temporary Files": return .green
        default: return .gray
        }
    }
}

// MARK: - API Key Config View

struct APIKeyConfigView: View {
    @ObservedObject var viewModel: AIAnalysisViewModel
    @State private var apiKey: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Configure OpenAI API Key")
                .font(.title2)
                .padding(.top)
            
            Text("To use AI analysis features, you need to provide an OpenAI API key. Your key is stored securely in the Keychain.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            SecureField("OpenAI API Key", text: $apiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Link("Get an API Key from OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.caption)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    viewModel.saveAPIKey(apiKey)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(apiKey.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 300)
        .onAppear {
            apiKey = viewModel.getAPIKey() ?? ""
        }
    }
}

// MARK: - Preview

struct AIAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        AIAnalysisView(viewModel: AIAnalysisViewModel())
    }
}