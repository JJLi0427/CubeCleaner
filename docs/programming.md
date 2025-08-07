# CubeCleaner - Programming Documentation

## Technology Stack

### Core Technologies
- **Language**: Swift 5.7+
- **UI Framework**: SwiftUI with some UIKit components where needed
- **Graphics**: Metal for 3D visualization
- **Data Storage**: Core Data for scan results and preferences
- **Concurrency**: Swift Concurrency (async/await) for background operations
- **AI Integration**: OpenAI API for language model integration

### Development Tools
- **IDE**: Xcode 14+
- **Dependency Management**: Swift Package Manager
- **Version Control**: Git
- **Testing**: XCTest for unit and UI testing
- **CI/CD**: GitHub Actions or similar

## Architecture

CubeCleaner follows the MVVM (Model-View-ViewModel) architecture pattern with a focus on separation of concerns and testability.

### Core Components

1. **Models**
   - `FileSystemItem`: Represents files and folders with metadata
   - `ScanResult`: Contains the complete scan data structure
   - `FilterCriteria`: Defines filtering rules
   - `AIRecommendation`: Represents AI-generated cleanup suggestions

2. **ViewModels**
   - `ScannerViewModel`: Manages scanning operations
   - `VisualizationViewModel`: Handles data preparation for visualization
   - `FileSystemViewModel`: Manages file operations
   - `AIAnalysisViewModel`: Handles AI integration and recommendations

3. **Views**
   - `MainView`: Primary application container
   - `CubeVisualizationView`: 3D visualization component
   - `SidebarView`: Navigation and filtering options
   - `DetailView`: Information about selected items
   - `AIRecommendationView`: Displays AI suggestions

4. **Services**
   - `FileSystemService`: Handles file system operations
   - `ScannerService`: Performs disk scanning
   - `PersistenceService`: Manages data storage
   - `AIService`: Handles communication with language models

## Module Breakdown

### File System Scanner

```swift
protocol FileSystemScannerProtocol {
    func scan(url: URL, excludedPaths: [String], depth: Int?) async throws -> ScanResult
    func cancelScan()
    var progress: Progress { get }
}

class FileSystemScanner: FileSystemScannerProtocol {
    // Implementation details
}
```

The scanner module is responsible for traversing the file system and collecting metadata about files and folders. It operates asynchronously to prevent UI blocking and provides progress updates.

**Key Features:**
- Efficient recursive directory traversal
- File metadata collection (size, dates, type)
- Progress reporting
- Cancellation support
- Error handling for permission issues

### Visualization Engine

```swift
protocol VisualizationEngineProtocol {
    func prepareVisualizationData(from scanResult: ScanResult, colorScheme: ColorScheme) -> VisualizationData
    func updateVisualization(with data: VisualizationData)
    func zoomTo(item: FileSystemItem)
}

class MetalVisualizationEngine: VisualizationEngineProtocol {
    // Implementation details
}
```

The visualization engine transforms scan data into a 3D representation using Metal. It handles rendering, interaction, and animation of the cube visualization.

**Key Features:**
- Efficient 3D rendering with Metal
- Dynamic cube generation based on file sizes
- Color mapping based on file attributes
- Interactive selection and navigation
- Smooth animations for transitions

### Data Model

```swift
struct FileSystemItem: Identifiable, Codable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let type: FileType
    let creationDate: Date?
    let modificationDate: Date?
    let accessDate: Date?
    var children: [FileSystemItem]?
    var parent: FileSystemItem?
    
    // Computed properties
    var isDirectory: Bool { /* ... */ }
    var formattedSize: String { /* ... */ }
    var relativeSizeToParent: Double { /* ... */ }
}

struct ScanResult: Codable {
    let rootItem: FileSystemItem
    let scanDate: Date
    let totalSize: Int64
    let itemCount: Int
    let scanPath: URL
}
```

The data model defines the structure for representing file system information and scan results. It includes serialization support for saving and loading scans.

### AI Integration

```swift
protocol AIServiceProtocol {
    func analyzeItems(_ items: [FileSystemItem]) async throws -> [AIRecommendation]
    func provideFeedback(for recommendation: AIRecommendation, wasHelpful: Bool)
}

class OpenAIService: AIServiceProtocol {
    // Implementation details
}

struct AIRecommendation: Identifiable, Codable {
    let id: UUID
    let targetItem: FileSystemItem
    let recommendationType: RecommendationType
    let confidence: Float
    let reasoning: String
    let suggestedAction: SuggestedAction
}
```

The AI integration module handles communication with language models to analyze file usage patterns and provide cleanup recommendations.

**Key Features:**
- Secure API communication
- Contextual prompting based on file metadata
- Processing and categorization of AI responses
- User feedback collection for improvement
- Fallback mechanisms for offline operation

### File Operations

```swift
protocol FileOperationsProtocol {
    func revealInFinder(url: URL) throws
    func moveToTrash(urls: [URL]) throws -> [URL]
    func deleteItems(urls: [URL]) throws
    func getQuickLookPreview(for url: URL) -> NSImage?
}

class FileOperationsManager: FileOperationsProtocol {
    // Implementation details
}
```

The file operations module provides a safe interface for performing actions on files and folders, including revealing in Finder, moving to trash, and permanent deletion.

### Persistence Layer

```swift
protocol PersistenceServiceProtocol {
    func saveScanResult(_ result: ScanResult) throws -> URL
    func loadScanResult(from url: URL) throws -> ScanResult
    func savePreferences(_ preferences: AppPreferences) throws
    func loadPreferences() throws -> AppPreferences
}

class CoreDataPersistenceService: PersistenceServiceProtocol {
    // Implementation details
}
```

The persistence layer handles saving and loading scan results, user preferences, and other application data.

## Implementation Plan

### Phase 1: Core Functionality
1. Set up project structure and architecture
2. Implement file system scanner
3. Create basic data models
4. Develop simple list-based visualization
5. Implement basic file operations

### Phase 2: Visualization
1. Implement Metal-based 3D visualization engine
2. Create interactive cube representation
3. Add color schemes and customization options
4. Implement navigation and selection in 3D view

### Phase 3: Advanced Features
1. Add filtering and search capabilities
2. Implement scan comparison functionality
3. Create detailed statistics and reports
4. Add export and sharing options

### Phase 4: AI Integration
1. Set up secure API communication
2. Implement file analysis algorithms
3. Create AI recommendation UI
4. Add feedback mechanisms for AI suggestions

### Phase 5: Polish and Optimization
1. Performance optimization for large file systems
2. UI refinement and animations
3. Accessibility improvements
4. Comprehensive testing and bug fixing

## Key Algorithms

### Disk Space Calculation
```swift
func calculateDirectorySize(url: URL) async throws -> Int64 {
    let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
    let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles],
        errorHandler: nil
    )
    
    var totalSize: Int64 = 0
    
    for case let fileURL as URL in enumerator! {
        let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
        if let fileSize = resourceValues.fileSize, !resourceValues.isDirectory! {
            totalSize += Int64(fileSize)
        }
    }
    
    return totalSize
}
```

### Treemap Layout Algorithm
```swift
func layoutTreemap(items: [FileSystemItem], rect: CGRect) -> [ItemLayout] {
    // Sort items by size (largest first)
    let sortedItems = items.sorted { $0.size > $1.size }
    
    // Calculate total size
    let totalSize = items.reduce(0) { $0 + $1.size }
    
    // Implement squarified treemap algorithm
    // This is a simplified representation of the algorithm
    var layouts: [ItemLayout] = []
    var remainingRect = rect
    
    for item in sortedItems {
        let ratio = Double(item.size) / Double(totalSize)
        let itemRect = calculateItemRect(in: remainingRect, ratio: ratio)
        layouts.append(ItemLayout(item: item, rect: itemRect))
        remainingRect = updateRemainingRect(remainingRect, used: itemRect)
    }
    
    return layouts
}
```

### AI Prompt Construction
```swift
func constructAIPrompt(for items: [FileSystemItem]) -> String {
    var prompt = """Analyze the following files and folders to determine which ones might be safe to delete or archive.
    For each item, consider its type, size, age, and location.
    Provide recommendations in the following format:
    - Item: [path]
    - Recommendation: [delete/archive/keep]
    - Confidence: [high/medium/low]
    - Reasoning: [brief explanation]
    
    Files and folders to analyze:
    """
    
    for item in items {
        let ageInDays = Calendar.current.dateComponents([.day], from: item.modificationDate ?? Date(), to: Date()).day ?? 0
        
        prompt += """\n- Path: \(item.url.path)
  Type: \(item.type.rawValue)
  Size: \(item.formattedSize)
  Last modified: \(ageInDays) days ago
  Parent folder: \(item.parent?.name ?? "root")
"""
    }
    
    return prompt
}
```

## Testing Strategy

### Unit Testing
- Test file system operations with mock file system
- Test scanning algorithms with known directory structures
- Test data model serialization and deserialization
- Test AI prompt construction and response parsing

### Integration Testing
- Test scanner integration with visualization
- Test AI service with real API (using test credentials)
- Test persistence layer with actual file operations

### UI Testing
- Test main user flows
- Test accessibility features
- Test responsive layout

### Performance Testing
- Benchmark scanning performance with large directories
- Test visualization performance with complex file structures
- Monitor memory usage during extended operations

## Security Considerations

1. **File System Access**
   - Request only necessary permissions
   - Handle permission errors gracefully
   - Provide clear explanations for permission requests

2. **AI API Integration**
   - Store API keys securely in Keychain
   - Transmit only necessary metadata, never file contents
   - Implement proper error handling for API failures

3. **Data Storage**
   - Encrypt saved scan results
   - Implement secure deletion when requested
   - Clear sensitive data from memory when no longer needed

## Deployment and Distribution

1. **Code Signing**
   - Sign application with Apple Developer certificate
   - Implement hardened runtime
   - Configure appropriate entitlements

2. **App Store Submission**
   - Prepare App Store Connect listing
   - Create marketing materials and screenshots
   - Write privacy policy and usage descriptions

3. **Updates**
   - Implement in-app update checking
   - Plan for feature additions and improvements
   - Maintain backward compatibility with saved scan data