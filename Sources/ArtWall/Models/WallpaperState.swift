import AppKit
import Foundation
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.baileywickham.ArtWall", category: "WallpaperState")

@Observable
@MainActor
final class WallpaperState {
    var catalog: Catalog?
    var currentImage: ArtImage?
    var dislikedIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(dislikedIds), forKey: "dislikedIds")
        }
    }
    var selectedPackIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedPackIds), forKey: "selectedPackIds")
        }
    }
    var autoRotateEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRotateEnabled, forKey: "autoRotateEnabled"); scheduleTimer() }
    }
    var rotateInterval: TimeInterval {
        didSet { UserDefaults.standard.set(rotateInterval, forKey: "rotateInterval"); scheduleTimer() }
    }
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem(userInitiated: true)
        }
    }
    private var lastRotationDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastRotationDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRotationDate") }
    }

    private var timer: Timer?
    private var spaceObserver: NSObjectProtocol?

    static let intervals: [(String, TimeInterval)] = [
        ("1 minute", 60),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600),
        ("2 hours", 7200),
        ("4 hours", 14400),
        ("Daily", 86400),
    ]

    var rotatePool: [ArtImage] {
        guard let catalog else { return [] }
        let base = selectedPackIds.isEmpty
            ? catalog.allAvailableImages
            : catalog.allAvailableImages.filter { selectedPackIds.contains($0.packId) }
        return base.filter { !dislikedIds.contains($0.id) }
    }

    var selectionLabel: String {
        guard let catalog else { return "All" }
        if selectedPackIds.isEmpty {
            return "All galleries"
        }
        let names = catalog.availablePacks
            .filter { selectedPackIds.contains($0.id) }
            .map(\.shortName)
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names.count) galleries"
    }

    init() {
        self.autoRotateEnabled = UserDefaults.standard.bool(forKey: "autoRotateEnabled")
        let saved = UserDefaults.standard.double(forKey: "rotateInterval")
        self.rotateInterval = saved > 0 ? saved : 86400
        self.launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
        if let savedIds = UserDefaults.standard.array(forKey: "selectedPackIds") as? [Int] {
            self.selectedPackIds = Set(savedIds)
        }
        if let savedDisliked = UserDefaults.standard.array(forKey: "dislikedIds") as? [String] {
            self.dislikedIds = Set(savedDisliked)
        }
        scheduleTimer()
        updateLoginItem()

        // macOS wallpaper APIs only affect the currently visible space, so
        // re-apply on every space switch to keep all spaces on the same image.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reapplyCurrent()
            }
        }
    }

    private func reapplyCurrent() {
        if currentImage == nil {
            restoreCurrent()
        }
        guard let catalog, let image = currentImage,
              let url = image.resolvedURL(relativeTo: catalog.dataDirectory) else { return }
        WallpaperService.setWallpaper(url: url)
    }

    func setRandom() {
        guard !rotatePool.isEmpty else { return }
        let image = rotatePool.randomElement()!
        setWallpaper(image)
    }

    func setWallpaper(_ image: ArtImage) {
        guard let catalog else { return }
        currentImage = image
        lastRotationDate = Date()
        UserDefaults.standard.set(image.id, forKey: "currentImageId")
        if let url = image.resolvedURL(relativeTo: catalog.dataDirectory) {
            WallpaperService.setWallpaper(url: url)
        }
    }

    func setNext() {
        let available = rotatePool
        guard !available.isEmpty else { return }
        if let current = currentImage, let idx = available.firstIndex(where: { $0.id == current.id }) {
            let next = available[(idx + 1) % available.count]
            setWallpaper(next)
        } else {
            setRandom()
        }
    }

    func togglePack(_ packId: Int) {
        if selectedPackIds.contains(packId) {
            selectedPackIds.remove(packId)
        } else {
            selectedPackIds.insert(packId)
        }
        autoRotateEnabled = true
    }

    func dislike(_ image: ArtImage) {
        dislikedIds.insert(image.id)
        if currentImage?.id == image.id {
            setRandom()
        }
    }

    func undislike(_ image: ArtImage) {
        dislikedIds.remove(image.id)
    }

    func isDisliked(_ image: ArtImage) -> Bool {
        dislikedIds.contains(image.id)
    }

    func selectAll() {
        selectedPackIds = []
        autoRotateEnabled = true
    }

    func restoreCurrent() {
        guard let catalog else { return }
        if let savedId = UserDefaults.standard.string(forKey: "currentImageId"),
           let image = catalog.images.first(where: { $0.id == savedId }) {
            currentImage = image
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoRotateEnabled else { return }
        // Schedule from the persisted last rotation, not from app launch —
        // otherwise a Mac that reboots more often than the interval never
        // rotates. Overdue rotations (e.g. after days powered off) fire
        // almost immediately, then the cycle continues from there.
        let elapsed = lastRotationDate.map { Date().timeIntervalSince($0) } ?? rotateInterval
        let delay = max(rotateInterval - elapsed, 1)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setRandom()
                self?.scheduleTimer()
            }
        }
    }

    private func updateLoginItem(userInitiated: Bool = false) {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                guard service.status != .enabled else { return }
                // Auto-register only on first run; if the user disabled the
                // login item in System Settings, don't fight them — only a
                // deliberate toggle in our Settings re-registers.
                if userInitiated || service.status == .notFound {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
