import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let catalog = Catalog()
    let wallpaperState = WallpaperState()
    let updateManager = UpdateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        catalog.load()
        wallpaperState.catalog = catalog

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
               let image = NSImage(contentsOf: iconURL) {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                button.title = "AW"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateManager.start()

        let contentView = MenuBarView()
            .environment(catalog)
            .environment(wallpaperState)
            .environment(updateManager)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
