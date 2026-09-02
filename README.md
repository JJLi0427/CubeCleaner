<p align="right">
  <a href="README.md">English</a> |
  <a href="doc/README-CN.md">简体中文</a>
</p>

<h1 align="center">
  <img src="assets/icon.png" width="48" />
  <br />
  CubeCleaner
</h1>

<p align="center">
  <em>A macOS disk space visualizer that turns your files into a <strong>TreeMap</strong> —<br />one glance to find out what's eating your hard drive.</em>
</p>

<p align="center">
  <a href="https://github.com/JJLi0427/CubeCleaner/releases">
    <img alt="macOS" src="https://img.shields.io/badge/-macOS%2015.5%2B-000000?style=flat-square&logo=apple&logoColor=white" />
  </a>
  <a href="https://github.com/JJLi0427/CubeCleaner/releases">
    <img alt="Downloads" src="https://img.shields.io/github/downloads/JJLi0427/CubeCleaner/total.svg?style=flat" />
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg" />
  </a>
  <a href="https://github.com/JJLi0427/CubeCleaner/actions/workflows/release.yml">
    <img alt="Build" src="https://github.com/JJLi0427/CubeCleaner/actions/workflows/release.yml/badge.svg" />
  </a>
</p>

<p align="center">
  <a href="assets/screenshot-1.png">
    <img src="assets/screenshot-1.png" width="400" />
  </a>
  <a href="assets/screenshot-2.png">
    <img src="assets/screenshot-2.png" width="400" />
  </a>
</p>

---

Inspired by [GrandPerspective](https://apps.apple.com/app/grandperspective/id1111570163), CubeCleaner is a modern SwiftUI implementation focused on scan performance and native macOS experience.

## 📥 Download

Download the latest version from [GitHub Releases](https://github.com/JJLi0427/CubeCleaner/releases).

> ⚠️ The DMG is **ad-hoc signed** (no Developer ID, not notarized). On first launch, Gatekeeper will block it. Right-click **CubeCleaner.app** → **Open** → Confirm, or after moving to `/Applications` run:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/CubeCleaner.app
> ```

## ✨ Features

- 🗺️ **TreeMap Visualization** — Rectangle area is strictly proportional to file/directory size. Spot space hogs at a glance.
- ⚡ **High-Performance Scan** — Uses `getattrlistbulk` for bulk file attribute reads; scanning runs on background threads with throttled progress updates.
- 🧩 **Small File Aggregation** — Files below threshold (1% of parent) are grouped into an "Other" block. Double-click to drill into the aggregated block.
- 🎨 **Type-Based Coloring** — Documents / Images / Videos / Audio / Archives / Apps / System files are color-coded. Deeper shades for larger items within the same type.
- 🖱️ **Rich Interactions** — Click to select, double-click to drill into a directory, long-press to reveal in Finder, hover for preview.
- 🧭 **Breadcrumb Navigation** — Current path shown at the top; click any segment to jump back, plus a dedicated "Back" button.
- 📊 **Live Statistics** — Total size / file count / folder count, type ratio bar, and a clickable type legend for highlighting.
- 🗑️ **Move to Trash** — One-click trash with confirmation dialog; auto re-scans after deletion.
- 🧠 **Smart Boundaries** — Hardlink / firmlink dedup, symlinks not followed, cross-volume subdirectories not recursed.
- 🖥️ **Canvas Rendering** — All rectangles painted in a single Canvas pass; resize debounced.

## 🚀 Quick Start

**Requirements**

- macOS 15.5+
- Xcode 16.0+

**Build from source**

```bash
git clone https://github.com/JJLi0427/CubeCleaner.git
cd CubeCleaner
open CubeCleaner.xcodeproj
```

Press **⌘R** in Xcode, or use the build script:

```bash
./build.sh build     # Debug build
./build.sh release   # Release build
./build.sh run       # Run the built app
```

## 🗂️ Project Structure

```
CubeCleaner/
├── CubeCleaner/                    # App source
│   ├── CubeCleanerApp.swift        # App entry point
│   ├── ContentView.swift           # Main layout
│   ├── DesignSystem.swift          # Design constants (radii / shadows)
│   ├── Models/                     # Data models
│   │   ├── FileSystemItem.swift
│   │   ├── FileSystemError.swift
│   │   ├── FileType.swift
│   │   ├── TreeNode.swift
│   │   └── TreeMapRectangle.swift
│   ├── Services/                   # Scan / layout / coloring
│   │   ├── BulkFileScanner.swift   # getattrlistbulk low-level scanner
│   │   ├── FileSystemService.swift # Scan orchestration
│   │   ├── BinaryTreeMapCalculator.swift  # Squarified TreeMap layout
│   │   └── ColorSchemeManager.swift       # Type coloring & stats
│   ├── Views/                      # SwiftUI views
│   │   ├── TreeMapCanvasView.swift
│   │   ├── NavigationBarView.swift / BreadcrumbView.swift
│   │   ├── StatsBarView.swift / TypeRatioBarView.swift / TypeLegendStripView.swift
│   │   ├── BottomDetailBarView.swift
│   │   └── EmptyStateView.swift
│   └── Extensions/
│       └── Array+Chunked.swift
├── CubeCleaner.xcodeproj/          # Xcode project
├── build.sh                        # Build script
└── README.md
```

## ⚙️ Technical Highlights

- **Scanning**: `getattrlistbulk` batches `name / fsid / objtype / fileid / datalength`; `FileManager` fallback on failure.
- **Dedup & Boundaries**: `(dev, ino)` dedup for hardlinks & firmlinks; symlinks marked as leaves; `getmntinfo` pre-builds mount-point set to skip cross-volume recursion.
- **Layout**: Squarified TreeMap (Bruls/Huijsen/van Wijk 2000) directly optimizes aspect ratio, eliminating thin strips.
- **Performance**: Total size cached bottom-up after scan (`O(1)` read); tree nodes are plain `class` objects (no `ObservableObject` overhead), refreshed by a single `rootNode` change.

## 📄 License

MIT License © CubeCleaner Contributors. See [LICENSE](LICENSE) for details.