# CubeCleaner

A macOS disk usage visualization application built with Swift and SwiftUI, inspired by GrandPerspective. CubeCleaner provides an intuitive tree map visualization of your disk usage, helping you identify large files and folders to manage your disk space effectively.

## Features

- 🗂️ **Visual Disk Analysis**: Tree map visualization showing files as rectangles proportional to their size
- 🎨 **Flexible Color Coding**: Color files by type, extension, size, date, or folder hierarchy
- 🔍 **Advanced Filtering**: Filter by file size, type, date, and custom criteria
- 📊 **Multiple Views**: Support for multiple simultaneous views and comparisons
- 💾 **Save & Export**: Save scan results and export as images or data files
- ⚡ **High Performance**: Optimized scanning and rendering for large file systems
- 🖱️ **Interactive Navigation**: Mouse and keyboard navigation with zoom and pan
- 🔗 **System Integration**: Quick Look preview, Finder integration, and file operations

## Documentation

This project includes comprehensive documentation to guide development:

- **[Requirements Documentation](docs/Requirements.md)** - Detailed functional and non-functional requirements
- **[Interface Design Documentation](docs/Interface-Design.md)** - UI/UX design specifications and interaction patterns  
- **[Programming Design Documentation](docs/Programming-Design.md)** - Architecture, models, and implementation details

## Project Structure

```
CubeCleaner/
├── docs/                          # Documentation
│   ├── Requirements.md
│   ├── Interface-Design.md
│   └── Programming-Design.md
├── CubeCleaner/
│   ├── CubeCleaner/              # Main application
│   │   ├── CubeCleanerApp.swift
│   │   ├── ContentView.swift
│   │   └── Assets.xcassets/
│   └── CubeCleaner.xcodeproj/    # Xcode project
└── README.md
```

## Getting Started

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Building the Project

1. Clone the repository:
   ```bash
   git clone https://github.com/JJLi0427/CubeCleaner.git
   cd CubeCleaner
   ```

2. Open the project in Xcode:
   ```bash
   open CubeCleaner/CubeCleaner.xcodeproj
   ```

3. Build and run the project (⌘+R)

## Development Roadmap

### Phase 1: Core Infrastructure
- [ ] Basic project setup and architecture
- [ ] File system scanning engine
- [ ] Tree data structure implementation
- [ ] Basic SwiftUI views

### Phase 2: Visualization
- [ ] Tree map layout algorithm
- [ ] Rectangle rendering system
- [ ] Color scheme implementation
- [ ] Interactive navigation

### Phase 3: User Interface
- [ ] Main window layout
- [ ] Sidebar and inspector panels
- [ ] Toolbar and menu system
- [ ] Preferences window

### Phase 4: Advanced Features
- [ ] Filtering system
- [ ] Search functionality
- [ ] Export capabilities
- [ ] Multiple view support

### Phase 5: Polish & Performance
- [ ] Performance optimization
- [ ] Error handling
- [ ] Accessibility features
- [ ] App Store preparation

## Contributing

We welcome contributions! Please read our contributing guidelines and feel free to submit issues and pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Inspiration

This project is inspired by [GrandPerspective](https://apps.apple.com/app/grandperspective/id1111570163), an excellent disk usage visualization tool for macOS. CubeCleaner aims to provide a modern, SwiftUI-based alternative with enhanced features and performance.