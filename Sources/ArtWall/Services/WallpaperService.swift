import AppKit

enum WallpaperService {
    static func setWallpaper(url: URL) {
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
