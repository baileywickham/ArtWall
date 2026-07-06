import AppKit
import os.log

private let logger = Logger(subsystem: "com.baileywickham.ArtWall", category: "WallpaperService")

enum WallpaperService {
    @MainActor
    static func setWallpaper(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Wallpaper file missing at \(url.path, privacy: .public)")
            return
        }

        setWallpaperOnAllScreens(url: url)
    }

    // macOS only applies desktop images to the space currently visible on
    // each display; WallpaperState re-applies on space switches so every
    // space converges to the current image.
    @MainActor
    private static func setWallpaperOnAllScreens(url: URL) {
        for screen in NSScreen.screens {
            do {
                let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                logger.error("Failed to set wallpaper on screen \(screen.localizedName): \(error.localizedDescription)")
            }
        }
    }
}
