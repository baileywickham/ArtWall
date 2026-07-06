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

        // Best-effort update for every macOS desktop/space. Requires the
        // Apple Events entitlement in signed builds. NSAppleScript must run
        // on the main thread.
        setWallpaperOnAllSpaces(url: url)
    }

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

    @MainActor
    private static func setWallpaperOnAllSpaces(url: URL) {
        let escapedPath = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: """
            tell application "System Events" to tell every desktop to set picture to "\(escapedPath)"
            """)

        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            logger.error("AppleScript failed: \(String(describing: errorInfo), privacy: .public)")
        }
    }
}
