# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is ArtWall

macOS menu bar app (Swift/SwiftUI) that sets art wallpapers from Artpaper image packs. Runs as a menu bar accessory (`LSUIElement`), no dock icon. Requires macOS 14+.

## Build & Run

```bash
swift build -c release          # Build release binary
swift build                     # Build debug
swift test                      # Run tests (no test targets yet)
.build/release/ArtWall          # Run the built binary
```

The release workflow (`scripts/build.sh`) creates a signed `.app` bundle, DMG, and ZIP. It requires `CODESIGN_IDENTITY` env var. Releases are triggered by pushing a `v*` tag.

## Image Data Setup

Images live in `Data/` (gitignored). Before running, extract images from a local Artpaper installation:

```bash
python3 scripts/extract_images.py --packs 2,14   # Local packs only
python3 scripts/extract_images.py                  # All packs (~1GB download)
```

This produces `Data/catalog.json` and `Data/images/pack_XX/` directories. The app reads `catalog.json` at startup via `Catalog.load()`.

## Architecture

Swift Package (swift-tools-version 5.10) with a single executable target. No external dependencies.

### Key layers

- **App/** — `ArtWallApp` (@main SwiftUI App) + `AppDelegate` (creates NSStatusItem, popover, wires up environment objects)
- **Models/** — `@Observable` state objects injected via SwiftUI `.environment()`:
  - `Catalog` — loads `catalog.json`, provides packs/images lookup
  - `WallpaperState` — rotation logic, dislike list, selected galleries, timer scheduling. All preferences persisted via `UserDefaults`
  - `ArtImage` / `ArtPack` — Codable data types
- **Services/**:
  - `WallpaperService` — sets wallpaper on all screens via `NSWorkspace`; `WallpaperState` re-applies it on space switches so all spaces match
  - `ImageLoader` — singleton with `NSCache`-backed thumbnail generation using `CGImageSource`
  - `UpdateChecker` — polls GitHub releases API, compares version strings
- **Views/** — SwiftUI views displayed in the popover:
  - `MenuBarView` — root tabbed view (Current / Browse) with rotation controls
  - `CurrentWallpaperView` — shows current wallpaper preview, metadata, Random/Next/Dislike buttons
  - `BrowseView` — pack list with checkboxes for rotation selection, drill-down grid of thumbnails
  - `SettingsView` — exposed via macOS Settings scene

### Data flow

`AppDelegate` creates `Catalog` and `WallpaperState`, injects them as SwiftUI `@Environment` objects. `WallpaperState` holds all mutable state (current image, selected packs, disliked images, rotation timer) and delegates actual wallpaper setting to `WallpaperService`.

### Data directory

The `Catalog` data directory is hardcoded to `~/workspace/ArtWall/Data`. The `extract_images.py` script writes to the same path.
