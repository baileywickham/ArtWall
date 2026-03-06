import AppKit

enum WallpaperService {
    static func setWallpaper(url: URL) {
        // Set across all spaces via AppleScript
        let script = NSAppleScript(source: """
            tell application "System Events" to tell every desktop to set picture to "\(url.path)"
            """)
        script?.executeAndReturnError(nil)

        // Set on all physical screens (covers secondary monitors)
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen)
        }
    }
}
