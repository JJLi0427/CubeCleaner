//
//  ScanOptionsView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI

struct ScanOptionsView: View {
    @State var parameters: ScanParameters
    var onSave: (ScanParameters) -> Void
    var onCancel: () -> Void
    
    @State private var excludedPathsText: String = ""
    
    init(parameters: ScanParameters, onSave: @escaping (ScanParameters) -> Void, onCancel: @escaping () -> Void) {
        self._parameters = State(initialValue: parameters)
        self.onSave = onSave
        self.onCancel = onCancel
        self._excludedPathsText = State(initialValue: parameters.excludedPaths.joined(separator: "\n"))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Scan Options")
                .font(.title2)
                .padding(.top)
            
            Form {
                Section(header: Text("Exclusions")) {
                    Toggle("Exclude Hidden Files", isOn: $parameters.excludeHiddenFiles)
                        .help("Files and folders that start with a dot (.)") 
                    Toggle("Exclude System Files", isOn: $parameters.excludeSystemFiles)
                        .help("System files and folders like /System, /Library, etc.")
                }
                
                Section(header: Text("Excluded Paths")) {
                    TextEditor(text: $excludedPathsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                    
                    Text("Enter one path per line. Paths can be absolute or relative to the scan root.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Scan Depth")) {
                    Picker("Maximum Depth", selection: Binding(
                        get: { parameters.maxDepth == nil ? 0 : parameters.maxDepth! },
                        set: { parameters.maxDepth = $0 == 0 ? nil : $0 }
                    )) {
                        Text("No Limit").tag(0)
                        ForEach(1...10, id: \.self) { depth in
                            Text("\(depth) levels").tag(depth)
                        }
                    }
                    .help("Limits how deep the scanner will traverse into subdirectories")
                }
                
                Section(header: Text("Package Handling")) {
                    Toggle("Scan Package Contents", isOn: $parameters.scanPackageContents)
                        .help("When enabled, the scanner will look inside .app and other package files")
                }
            }
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    // Update excluded paths from text
                    let paths = excludedPathsText
                        .split(separator: "\n")
                        .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .filter { !$0.isEmpty }
                    
                    parameters.excludedPaths = paths
                    
                    // Save parameters
                    onSave(parameters)
                }
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}

struct ScanOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ScanOptionsView(
            parameters: ScanParameters(),
            onSave: { _ in },
            onCancel: {}
        )
    }
}