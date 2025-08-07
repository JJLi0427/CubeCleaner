//
//  VisualizationView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct VisualizationView: View {
    @ObservedObject var viewModel: VisualizationViewModel
    @State private var showColorSchemeMenu = false
    @State private var showVisualizationModeMenu = false
    
    var body: some View {
        ZStack {
            // Main visualization area
            MetalView(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Loading overlay
            if viewModel.isLoading {
                loadingOverlay
            }
            
            // Error message
            if let errorMessage = viewModel.errorMessage {
                errorOverlay(message: errorMessage)
            }
            
            // Controls overlay
            VStack {
                // Top controls
                topControls
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            .padding()
        }
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text("Preparing Visualization...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color.gray.opacity(0.7))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Error Overlay
    
    private func errorOverlay(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.yellow)
                
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Button("Dismiss") {
                    viewModel.errorMessage = nil
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(30)
            .background(Color.gray.opacity(0.7))
            .cornerRadius(10)
            .frame(maxWidth: 400)
        }
    }
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack {
            // Breadcrumb navigation
            breadcrumbView
            
            Spacer()
            
            // Search field
            searchField
        }
        .padding(8)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(8)
    }
    
    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.breadcrumbItems, id: \.id) { item in
                    Button(action: {
                        viewModel.navigateToItem(item)
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                .font(.caption)
                            
                            Text(item.name)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if item != viewModel.breadcrumbItems.last {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search", text: $viewModel.searchText, onCommit: {
                viewModel.search(for: viewModel.searchText)
            })
            .textFieldStyle(PlainTextFieldStyle())
            .frame(width: 200)
            
            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                    viewModel.search(for: "")
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        HStack {
            // Navigation controls
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.resetView()
                }) {
                    Image(systemName: "house.fill")
                        .font(.title3)
                }
                .help("Return to root")
                
                Button(action: {
                    viewModel.navigateUp()
                }) {
                    Image(systemName: "arrow.up")
                        .font(.title3)
                }
                .help("Navigate up one level")
                .disabled(viewModel.breadcrumbItems.count <= 1)
            }
            
            Spacer()
            
            // Visualization controls
            HStack(spacing: 12) {
                // Color scheme menu
                Menu {
                    Button("File Type", action: { viewModel.changeColorScheme(.fileType) })
                    Button("Modification Date", action: { viewModel.changeColorScheme(.modificationDate) })
                    Button("Size", action: { viewModel.changeColorScheme(.size) })
                    Button("Parent Folder", action: { viewModel.changeColorScheme(.parentFolder) })
                } label: {
                    Label("Color: \(viewModel.colorScheme.displayName)", systemImage: "paintpalette")
                }
                
                // Visualization mode menu
                Menu {
                    Button("Cube", action: { viewModel.changeVisualizationMode(.cube) })
                    Button("Treemap", action: { viewModel.changeVisualizationMode(.treemap) })
                } label: {
                    Label("View: \(viewModel.visualizationMode.displayName)", systemImage: "square.3.stack.3d")
                }
                
                // Display options
                Menu {
                    Toggle("Show Hidden Files", isOn: $viewModel.showHiddenFiles)
                        .onChange(of: viewModel.showHiddenFiles) { _ in
                            viewModel.toggleShowHiddenFiles()
                        }
                    
                    Toggle("Show Package Contents", isOn: $viewModel.showPackageContents)
                        .onChange(of: viewModel.showPackageContents) { _ in
                            viewModel.toggleShowPackageContents()
                        }
                } label: {
                    Label("Options", systemImage: "gearshape")
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(8)
    }
}

// MARK: - Extensions

extension ColorScheme {
    var displayName: String {
        switch self {
        case .fileType: return "File Type"
        case .modificationDate: return "Date"
        case .size: return "Size"
        case .parentFolder: return "Folder"
        default: return "Default"
        }
    }
}

extension VisualizationMode {
    var displayName: String {
        switch self {
        case .cube: return "Cube"
        case .treemap: return "Treemap"
        }
    }
}

// MARK: - Preview

struct VisualizationView_Previews: PreviewProvider {
    static var previews: some View {
        VisualizationView(viewModel: VisualizationViewModel())
    }
}