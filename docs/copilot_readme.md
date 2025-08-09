# CubeCleaner Development Workspace

This workspace is configured for GitHub Copilot to provide comprehensive assistance across development, documentation, requirements, and progress tracking.

## Copilot Configuration

### Response Structure
Every Copilot response will include:

1. **🔧 Development**: Code implementation, architecture guidance, testing
2. **📚 Documentation**: API docs, comments, examples, guides
3. **📋 Requirements**: Requirement changes, priority updates, tracking
4. **📊 Progress**: Task status, milestone progress, metrics

### Project Context
- **Project**: CubeCleaner - macOS disk space analyzer
- **Tech Stack**: Swift, SwiftUI, Combine, Core Data
- **Architecture**: MVVM pattern with async/await
- **Target**: macOS 12.0+

### Automatic Updates
- Progress tracking in `PROJECT_PROGRESS.md`
- Requirements tracking in `docs/Requirements.md`
- Documentation generation for new code
- Work log entries for development activities

## Usage

When working with Copilot in this workspace:

1. **Ask for features**: Copilot will provide implementation + update all tracking
2. **Request explanations**: Get detailed docs + requirement context
3. **Debug issues**: Receive solutions + progress impact analysis
4. **Planning help**: Get roadmap + milestone updates

## File Structure

```
├── PROJECT_PROGRESS.md          # Main progress tracking
├── .copilot-instructions.md     # Copilot guidelines
├── .vscode/copilot.json        # Copilot configuration
├── docs/                       # Project documentation
└── CubeCleaner/               # Source code
```

## Getting Started

1. Open any file in the project
2. Use Copilot chat or inline suggestions
3. Copilot will automatically consider project context
4. All responses include the 4-part structure
5. Progress and documentation are auto-updated

---

**Last Updated**: 2025年8月9日
**Configuration Version**: 1.0.0
