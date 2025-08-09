# CubeCleaner - Interface Design Documentation

## 1. Design Overview

### 1.1 Design Philosophy
CubeCleaner follows Apple's Human Interface Guidelines with a focus on:
- **Clarity**: Clear visual hierarchy and intuitive navigation
- **Deference**: Content-focused design with minimal UI chrome
- **Depth**: Layered interface with realistic motion and depth

### 1.2 Visual Design Language
- **Color Palette**: Dynamic colors that adapt to system appearance
- **Typography**: San Francisco font family for consistency
- **Iconography**: SF Symbols for native macOS feel
- **Spacing**: 8pt grid system for consistent layout
- **Animations**: Smooth, physics-based transitions

## 2. Application Structure

### 2.1 Window Hierarchy
```
MainWindow
├── MenuBar
├── Toolbar
├── ContentView
│   ├── Sidebar (File Navigator)
│   ├── VisualizationView (TreeMap)
│   └── InspectorPanel
└── StatusBar
```

### 2.2 Navigation Flow
```
Launch Screen → Disk Selection → Scanning Progress → Main Interface
                     ↓
              Save/Load Results ← Filter Configuration
                     ↓
              Export Options ← Color Scheme Settings
```

## 3. User Interface Components

### 3.1 Main Window Layout

#### 3.1.1 Window Structure
```
┌─────────────────────────────────────────────────────────────┐
│ File  Edit  View  Scan  Window  Help                       │ Menu Bar
├─────────────────────────────────────────────────────────────┤
│ [Scan] [Refresh] [Filter] [Export] [Settings]              │ Toolbar
├─────────────────────────────────────────────────────────────┤
│ ┌─Sidebar─┐ │ ┌──────── TreeMap View ────────┐ ┌Inspector┐ │
│ │ Volumes  │ │ │                              │ │ Details │ │
│ │ ├ Disk1  │ │ │    ┌─────┐ ┌──┐ ┌─────────┐ │ │ ┌─────┐ │ │
│ │ ├ Disk2  │ │ │    │     │ │  │ │         │ │ │ │File │ │ │
│ │ └ USB    │ │ │    │     │ │  │ │         │ │ │ │Info │ │ │
│ │          │ │ │    └─────┘ └──┘ └─────────┘ │ │ └─────┘ │ │
│ │ Filters  │ │ │                              │ │        │ │
│ │ ├ Size   │ │ │    ┌───────────────────────┐ │ │ Colors │ │
│ │ ├ Type   │ │ │    │                       │ │ │ ┌─────┐ │ │
│ │ └ Date   │ │ │    │                       │ │ │ │     │ │ │
│ │          │ │ │    └───────────────────────┘ │ │ └─────┘ │ │
│ └──────────┘ │ └──────────────────────────────┘ └─────────┘ │
├─────────────────────────────────────────────────────────────┤
│ Scanning: /Users/username/Documents... 47% │ 2.3GB scanned │ Status Bar
└─────────────────────────────────────────────────────────────┘
```

#### 3.1.2 Responsive Layout
- **Minimum Width**: 1000px
- **Minimum Height**: 700px
- **Sidebar**: Collapsible, 200-300px width
- **Inspector**: Toggleable, 250px width
- **TreeMap**: Expandable main content area

### 3.2 Menu Bar Structure

#### 3.2.1 File Menu
```
File
├── New Scan...                    ⌘N
├── Open Scan Results...           ⌘O
├── Save Scan Results...           ⌘S
├── Save As...                     ⇧⌘S
├── ─────────────────
├── Export as Image...             ⌘E
├── Export as Text...              ⌥⌘E
├── ─────────────────
├── Close Window                   ⌘W
└── Quit CubeCleaner               ⌘Q
```

#### 3.2.2 Edit Menu
```
Edit
├── Undo                          ⌘Z
├── Redo                          ⇧⌘Z
├── ─────────────────
├── Cut                           ⌘X
├── Copy                          ⌘C
├── Paste                         ⌘V
├── Select All                    ⌘A
├── ─────────────────
└── Find...                       ⌘F
```

#### 3.2.3 View Menu
```
View
├── Show Sidebar                  ⌥⌘S
├── Show Inspector                ⌥⌘I
├── Show Status Bar               ⌘/
├── ─────────────────
├── Zoom In                       ⌘+
├── Zoom Out                      ⌘-
├── Zoom to Fit                   ⌘0
├── Actual Size                   ⌘1
├── ─────────────────
├── Color Scheme ►
│   ├── By File Type
│   ├── By Extension
│   ├── By Size
│   ├── By Date Modified
│   └── By Folder
├── ─────────────────
└── Full Screen                   ⌃⌘F
```

### 3.3 Toolbar Design

#### 3.3.1 Primary Actions
```
[📁 Scan] [🔄 Refresh] [🔍 Search] [⚙️ Filter] [📊 Export] [⚙️ Settings]
```

#### 3.3.2 Toolbar Items Specification
| Icon | Label | Action | Shortcut |
|------|-------|---------|----------|
| 📁 | Scan | Open folder selection dialog | ⌘N |
| 🔄 | Refresh | Rescan current directory | ⌘R |
| 🔍 | Search | Open search panel | ⌘F |
| ⚙️ | Filter | Toggle filter panel | ⌘⇧F |
| 📊 | Export | Export current view | ⌘E |
| ⚙️ | Settings | Open preferences | ⌘, |

### 3.4 Sidebar Components

#### 3.4.1 Volume Navigator
```
┌─ Volumes ─────────────────┐
│ 🖥️ Macintosh HD (250GB)   │
│   ├ 📁 Applications       │
│   ├ 📁 Users              │
│   ├ 📁 System             │
│   └ 📁 Library            │
│                           │
│ 💾 External Drive (1TB)   │
│   ├ 📁 Backups           │
│   └ 📁 Media             │
└───────────────────────────┘
```

#### 3.4.2 Filter Panel
```
┌─ Filters ─────────────────┐
│ File Size                 │
│ ○ All files              │
│ ○ > 1 MB                 │
│ ○ > 100 MB               │
│ ● > 1 GB                 │
│ ○ Custom: [___] MB       │
│                          │
│ File Type                │
│ ☑ Documents             │
│ ☑ Images                │
│ ☑ Videos                │
│ ☐ Applications          │
│ ☐ System Files          │
│                          │
│ Date Modified            │
│ ○ Any time              │
│ ○ Last week             │
│ ● Last month            │
│ ○ Last year             │
│ ○ Custom range...       │
│                          │
│ [Clear All] [Apply]      │
└──────────────────────────┘
```

### 3.5 TreeMap Visualization

#### 3.5.1 Rectangle Rendering
- **Size Mapping**: Area proportional to file size
- **Color Coding**: Configurable color schemes
- **Border Style**: 1px solid border, darker shade of fill color
- **Text Labels**: File names when rectangle size permits
- **Hover Effects**: Subtle shadow and brightness increase

#### 3.5.2 Color Schemes

##### By File Type
```
Documents:   Blue (#007AFF)
Images:      Green (#34C759)
Videos:      Red (#FF3B30)
Audio:       Purple (#AF52DE)
Archives:    Orange (#FF9500)
Applications: Gray (#8E8E93)
System:      Yellow (#FFCC00)
Other:       Light Gray (#C7C7CC)
```

##### By Size
```
< 1MB:       Light Blue (#ADD8E6)
1MB - 10MB:  Blue (#007AFF)
10MB - 100MB: Dark Blue (#0051D5)
100MB - 1GB: Purple (#AF52DE)
> 1GB:       Red (#FF3B30)
```

#### 3.5.3 Interactive Elements
- **Click**: Navigate into folder
- **Right-click**: Context menu
- **Hover**: Show tooltip with file details
- **Double-click**: Open file/reveal in Finder
- **Cmd+click**: Multi-select
- **Scroll**: Zoom in/out

### 3.6 Inspector Panel

#### 3.6.1 File Information
```
┌─ Inspector ───────────────┐
│ 📄 document.pdf          │
│                          │
│ Size: 2.3 MB             │
│ Type: PDF Document       │
│ Created: Aug 1, 2025     │
│ Modified: Aug 7, 2025    │
│ Path: /Users/docs/       │
│                          │
│ ┌─ Quick Actions ──────┐ │
│ │ [👁 Preview]         │ │
│ │ [📁 Show in Finder]  │ │
│ │ [🗑 Move to Trash]   │ │
│ └──────────────────────┘ │
│                          │
│ ┌─ Color Legend ───────┐ │
│ │ ■ PDF Files          │ │
│ │ ■ Image Files        │ │
│ │ ■ Video Files        │ │
│ │ ■ Other Files        │ │
│ └──────────────────────┘ │
└──────────────────────────┘
```

### 3.7 Modal Dialogs

#### 3.7.1 Scan Directory Dialog
```
┌─ Select Directory to Scan ──────────────────────────┐
│                                                     │
│ Choose a directory or volume to analyze:            │
│                                                     │
│ ┌─ Volumes ──────────────────────────────────────┐  │
│ │ 🖥️ Macintosh HD                              │  │
│ │ 💾 External Drive                            │  │
│ │ ☁️ iCloud Drive                              │  │
│ │ 🌐 Network Locations                         │  │
│ │   └ 🖥️ MacBook Air                          │  │
│ └─────────────────────────────────────────────────┘  │
│                                                     │
│ ☑ Scan package contents                            │
│ ☑ Include hidden files                             │
│ ☐ Follow symbolic links                            │
│                                                     │
│                              [Cancel] [Scan]       │
└─────────────────────────────────────────────────────┘
```

#### 3.7.2 Progress Dialog
```
┌─ Scanning Directory ─────────────────────────────────┐
│                                                     │
│ Scanning: /Users/username/Documents/Projects/      │
│                                                     │
│ ████████████████░░░░ 67%                           │
│                                                     │
│ Files scanned: 15,847                              │
│ Total size: 2.3 GB                                 │
│ Elapsed time: 0:23                                 │
│                                                     │
│                                      [Cancel]      │
└─────────────────────────────────────────────────────┘
```

### 3.8 Preferences Window

#### 3.8.1 General Tab
```
┌─ Preferences ──────────────────────────────────────────┐
│ [General] [Appearance] [Scanning] [Advanced]          │
│                                                        │
│ Startup                                                │
│ ○ Show welcome screen                                  │
│ ● Remember last scan                                   │
│ ○ Automatically scan default drive                     │
│                                                        │
│ File Operations                                        │
│ ☑ Confirm before deleting files                       │
│ ☑ Show files in Trash instead of permanent deletion   │
│ ☐ Show hidden files by default                        │
│                                                        │
│ Interface                                              │
│ ☑ Show file count in status bar                       │
│ ☑ Show tooltips                                        │
│ Default view: [TreeMap    ▼]                          │
│                                                        │
│                              [Reset] [Cancel] [OK]    │
└────────────────────────────────────────────────────────┘
```

## 4. Interaction Design

### 4.1 Navigation Patterns

#### 4.1.1 Primary Navigation
- **Breadcrumb Trail**: Show current path with clickable segments
- **Back/Forward**: Browser-style navigation through view history
- **Up Level**: Navigate to parent directory
- **Home**: Return to root level

#### 4.1.2 Zoom and Pan
- **Mouse Wheel**: Zoom in/out at cursor position
- **Trackpad**: Pinch-to-zoom and two-finger pan
- **Keyboard**: +/- for zoom, arrow keys for pan
- **Fit to Window**: Auto-scale to show entire tree

### 4.2 Selection and Multi-Selection

#### 4.2.1 Selection Modes
- **Single Click**: Select file/folder
- **Cmd+Click**: Add to selection
- **Shift+Click**: Range selection
- **Drag Selection**: Rectangle selection tool

#### 4.2.2 Selection Feedback
- **Visual**: Selected items have blue highlight
- **Inspector**: Shows details of selected item(s)
- **Context Menu**: Appropriate actions for selection

### 4.3 Keyboard Shortcuts

#### 4.3.1 Navigation Shortcuts
| Shortcut | Action |
|----------|--------|
| ↑↓←→ | Navigate selection |
| Space | Quick Look preview |
| Enter | Open/navigate into |
| ⌘↑ | Go up one level |
| ⌘[ | Go back |
| ⌘] | Go forward |

#### 4.3.2 View Shortcuts
| Shortcut | Action |
|----------|--------|
| ⌘+ | Zoom in |
| ⌘- | Zoom out |
| ⌘0 | Fit to window |
| ⌘1 | Actual size |
| ⌘L | Show/hide sidebar |

## 5. Responsive Design

### 5.1 Window Sizing
- **Small Window** (1000x700): Collapsed sidebar, essential controls only
- **Medium Window** (1400x900): Standard layout with all panels
- **Large Window** (1800+x1200+): Expanded panels, additional details

### 5.2 Adaptive Interface
- **Sidebar**: Auto-hide on small windows
- **Inspector**: Contextual showing/hiding
- **Toolbar**: Iconified on narrow windows
- **Status Bar**: Abbreviated information on small windows

## 6. Accessibility

### 6.1 VoiceOver Support
- **Navigation**: Full keyboard navigation support
- **Labels**: Descriptive labels for all UI elements
- **Hierarchy**: Proper heading structure
- **Descriptions**: Alternative text for visual elements

### 6.2 Keyboard Accessibility
- **Tab Order**: Logical tab sequence through interface
- **Focus Indicators**: Clear visual focus indicators
- **Shortcuts**: All functionality available via keyboard
- **Escape Routes**: Easy exit from any interaction mode

### 6.3 Visual Accessibility
- **Contrast**: WCAG AA compliance for text contrast
- **Color Independence**: Information not conveyed by color alone
- **Text Size**: Support for system text size preferences
- **Reduced Motion**: Respect reduced motion preferences

## 7. Animation and Transitions

### 7.1 View Transitions
- **Navigation**: 300ms ease-in-out slide transitions
- **Zoom**: 200ms ease-out scale transitions
- **Loading**: Smooth progress indicators
- **Hover**: 100ms color/shadow transitions

### 7.2 Data Updates
- **Refresh**: Subtle fade-out/fade-in for content updates
- **Real-time**: Smooth size adjustments during scanning
- **Filtering**: 250ms fade for show/hide elements

## 8. Dark Mode Support

### 8.1 Color Adaptations
- **Background**: Dynamic system colors
- **Text**: High contrast in both modes
- **Accents**: System accent color integration
- **Rectangles**: Adjusted saturation for dark backgrounds

### 8.2 Asset Variations
- **Icons**: SF Symbols with automatic adaptation
- **Custom Graphics**: Separate light/dark variants
- **Overlays**: Appropriate opacity for each mode
