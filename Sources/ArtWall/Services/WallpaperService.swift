import AppKit

enum WallpaperService {
    static func setWallpaper(url: URL) {
        let script = NSAppleScript(source: """
            tell application "System Events" to tell every desktop to set picture to "\(url.path)"
            """)
        script?.executeAndReturnError(nil)
    }
}
