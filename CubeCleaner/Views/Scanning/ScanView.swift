//
//  ScanView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct ScanView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @State private var showFolderPicker = false
    @State private var showScanOptions = false
    @State private var showSaveDialog = false
    @State private var showLoadDialog = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Scan controls
            scanControls
                .padding()
                .background(Color.secondary.opacity(0.1))
            
            // Scan progress or results
            if viewModel.isScanning {
                scanProgressView
                    .transition(.opacity)
            } else if let currentScan = viewModel.currentScanResult {
                scanResultView(for: currentScan)
                    .transition(.opacity)
            } else {
                emptyScanView
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showScanOptions) {
            ScanOptionsView(
                parameters: viewModel.scanParameters,
                onSave: { newParameters in
                    viewModel.updateScanParameters(newParameters)
                    showScanOptions = false
                },
                onCancel: {
                    showScanOptions = false
                }
            )
        }
    }
    
    // MARK: - Scan Controls
    
    private var scanControls: some View {
        HStack {
            // New scan button
            Button(action: {
                showFolderPicker = true
            }) {
                Label("New Scan", systemImage: "doc.viewfinder")
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
            
            // Scan options button
            Button(action: {
                showScanOptions = true
            }) {
                Label("Scan Options", systemImage: "gearshape")
            }
            
            Spacer()
            
            // Recent scans menu
            if !viewModel.recentScans.isEmpty {
                Menu {
                    ForEach(viewModel.recentScans) { scan in
                        Button(action: {
                            viewModel.loadScanResult(scan)
                        }) {
                            Label(
                                scan.scanPath,
                                systemImage: "folder"
                            )
                        }
                    }
                    
                    Divider()
                    
                    Button(action: {
                        viewModel.clearRecentScans()
                    }) {
                        Label("Clear Recent Scans", systemImage: "trash")
                    }
                } label: {
                    Label("Recent", systemImage: "clock")
                }
            }
            
            // Save/Load buttons
            Button(action: {
                showSaveDialog = true
            }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.currentScanResult == nil)
            .fileExporter(
                isPresented: $showSaveDialog,
                document: ScanResultDocument(scanResult: viewModel.currentScanResult),
                contentType: .json,
                defaultFilename: "Scan_\(Date().formatted(date: .numeric, time: .omitted))"
            ) { result in
                // Handle save result if needed
            }
            
            Button(action: {
                showLoadDialog = true
            }) {
                Label("Load", systemImage: "square.and.arrow.up")
            }
            .fileImporter(
                isPresented: $showLoadDialog,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }
    
    // MARK: - Scan Progress View
    
    private var scanProgressView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView(value: viewModel.scanProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 300)
            
            Text("Scanning: \(viewModel.scanProgress * 100, specifier: "%.1f")%")
                .font(.headline)
            
            Text(viewModel.currentScanPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 300)
            
            Button("Cancel") {
                viewModel.cancelScan()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Scan Result View
    
    private func scanResultView(for scan: ScanResult) -> some View {
        VStack(spacing: 16) {
            // Scan summary
            GroupBox(label: Label("Scan Summary", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Path:")
                            .bold()
                        Text(scan.scanPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    HStack {
                        Text("Date:")
                            .bold()
                        Text(scan.scanDate, format: .dateTime)
                    }
                    
                    HStack {
                        Text("Total Size:")
                            .bold()
                        Text(FileSystemItem.formatSize(scan.totalSize))
                    }
                    
                    HStack {
                        Text("Items:")
                            .bold()
                        Text("\(scan.itemCount)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            
            // File type distribution
            if let children = scan.rootItem.children {
                let fileTypeDistribution = Dictionary(grouping: children, by: { $0.type })
                    .mapValues { items in
                        items.reduce(0) { $0 + $1.size }
                    }
                    .sorted { $0.value > $1.value }
                
                GroupBox(label: Label("File Type Distribution", systemImage: "chart.pie")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(fileTypeDistribution.prefix(5), id: \.key) { type, size in
                            HStack {
                                Circle()
                                    .fill(Color(type.defaultColor))
                                    .frame(width: 12, height: 12)
                                
                                Text(type.rawValue)
                                    .frame(width: 100, alignment: .leading)
                                
                                Text(FileSystemItem.formatSize(size))
                                    .frame(width: 80, alignment: .trailing)
                                
                                ProgressView(value: Double(size), total: Double(scan.totalSize))
                                    .progressViewStyle(LinearProgressViewStyle())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal)
            }
            
            // Largest items
            let largestItems = scan.getLargestItems(count: 5)
            
            GroupBox(label: Label("Largest Items", systemImage: "arrow.up.forward.app")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(largestItems) { item in
                        HStack {
                            Image(systemName: item.type.systemImageName)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .lineLimit(1)
                                
                                Text(item.url.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text(item.formattedSize)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Notify that this item was selected
                            NotificationCenter.default.post(
                                name: .didSelectScanItem,
                                object: item
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            
            // Oldest items
            let oldestItems = scan.getOldestItems(count: 5)
            
            GroupBox(label: Label("Oldest Items", systemImage: "clock")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(oldestItems) { item in
                        HStack {
                            Image(systemName: item.type.systemImageName)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .lineLimit(1)
                                
                                if let date = item.modificationDate {
                                    Text(date, format: .dateTime)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Text("\(item.ageInDays) days old")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Notify that this item was selected
                            NotificationCenter.default.post(
                                name: .didSelectScanItem,
                                object: item
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    // MARK: - Empty Scan View
    
    private var emptyScanView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Scan Results")
                .font(.title2)
            
            Text("Start a new scan or load a previous scan result.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Start New Scan") {
                showFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            
            // Start scan with selected folder
            viewModel.startScan(path: selectedURL)
            
        case .failure(let error):
            viewModel.errorMessage = "Failed to select folder: \(error.localizedDescription)"
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            
            // Load scan result from file
            Task {
                _ = await viewModel.loadScanResultFromFile(at: selectedURL)
            }
            
        case .failure(let error):
            viewModel.errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }
}



// MARK: - ScanResultDocument

struct ScanResultDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var scanResult: ScanResult?
    
    init(scanResult: ScanResult? = nil) {
        self.scanResult = scanResult
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoder = JSONDecoder()
        self.scanResult = try decoder.decode(ScanResult.self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let scanResult = scanResult else {
            let emptyData = Data()
            return FileWrapper(regularFileWithContents: emptyData)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(scanResult)
        
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didSelectScanItem = Notification.Name("ScanViewDidSelectItem")
}

// MARK: - Preview

struct ScanView_Previews: PreviewProvider {
    static var previews: some View {
        ScanView(viewModel: ScannerViewModel())
    }
}