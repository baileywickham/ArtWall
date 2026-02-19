# ArtWall

macOS menu bar app that sets art wallpapers from [Artpaper](https://apps.apple.com/app/artpaper/id1448139498) image packs.

**[Download latest release](https://github.com/baileywickham/ArtWall/releases/latest)**

## Setup

Requires Artpaper to be installed (image metadata lives in the app bundle).

```bash
# Extract local images (packs you've downloaded in Artpaper)
python3 scripts/extract_images.py --packs 2,14

# Download all remote images (~1GB)
python3 scripts/extract_images.py

# Build and run
swift build -c release
.build/release/ArtWall
```

## Launch at login

```bash
cp com.baileywickham.ArtWall.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.baileywickham.ArtWall.plist
```

## Features

- Browse galleries and tap images to set as wallpaper
- Select one or more galleries to rotate through
- Auto-rotate on a schedule (1 min to daily)
- Dislike images to filter them from future rotations
- Sets wallpaper on all connected screens
