import SwiftUI

@main
struct ArtWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.catalog)
                .environment(appDelegate.wallpaperState)
        }
    }
}
