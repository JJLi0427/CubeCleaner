# CubeCleaner

Scan, visualize, and clean your Mac's storage—effortlessly see folder sizes and free up space.

## Features

### Disk Scanning
- Scan files and folders to analyze disk usage
- Configure scan parameters (depth, exclusions, etc.)
- Save and load scan results
- Track scan history

### 3D Visualization
- View disk usage as interactive 3D cubes
- Color files by type, modification date, size, parent folder, etc.
- Navigate through the file hierarchy
- Search for specific files
- Show/hide hidden files and package contents

### AI Analysis
- AI-powered recommendations for file cleanup
- Identify unused, rarely used, duplicate, and temporary files
- Get detailed explanations for each recommendation
- Potential space savings calculations

### User-Friendly Interface
- Intuitive tabbed interface
- Detailed file information
- Quick actions for common tasks
- Customizable settings

## Requirements

- macOS 12.0 or later
- Metal-compatible GPU

## Project Structure

- **Models**: Data structures for file system items, scan results, etc.
- **Views**: SwiftUI views for the user interface
- **ViewModels**: View models that connect the UI with the business logic
- **Services**: Core functionality for scanning, visualization, and AI analysis
- **Rendering**: Metal shaders and rendering code for 3D visualization
- **Utilities**: Helper functions and extensions

## AI Integration

CubeCleaner uses the OpenAI API to analyze files and provide cleanup recommendations. To use this feature:

1. Obtain an API key from [OpenAI](https://platform.openai.com/api-keys)
2. Enter your API key in the app's settings
3. Run a scan and use the AI Analysis tab to get recommendations
