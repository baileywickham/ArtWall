import AppKit
import os.log

private let logger = Logger(subsystem: "com.baileywickham.ArtWall", category: "WallpaperService")

enum WallpaperService {
    static func setWallpaper(url: URL) {
        // Set across all spaces via AppleScript
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: """
            tell application "System Events" to tell every desktop to set picture to "\(url.path)"
            """)
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            logger.error("AppleScript failed: \(errorInfo)")
        }

        // Set on all physical screens (covers secondary monitors)
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
            } catch {
                logger.error("Failed to set wallpaper on screen \(screen.localizedName): \(error.localizedDescription)")
            }
        }
    }
}
