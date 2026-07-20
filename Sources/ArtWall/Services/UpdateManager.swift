import AppKit
import Sparkle

/// Fully-silent Sparkle updater. Checks daily, downloads and stages updates in
/// the background, and exposes `updateReady` so the popover can offer
/// "Restart to update" — a menu bar app rarely quits, so without that button a
/// staged update would wait indefinitely for the next relaunch.
@MainActor
@Observable
final class UpdateManager: NSObject {
    private(set) var updateReady = false

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var driver: SilentUserDriver?
    @ObservationIgnored private var installNow: (() -> Void)?

    func start() {
        // Bare `swift build` binaries have no bundle to update.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        let driver = SilentUserDriver()
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: self
        )
        self.driver = driver
        self.updater = updater
        do {
            try updater.start()
        } catch {
            NSLog("ArtWall: Sparkle failed to start: \(error)")
        }
    }

    func relaunchToUpdate() {
        installNow?()
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        Task { @MainActor in
            self.installNow = immediateInstallationBlock
            self.updateReady = true
        }
        return true
    }
}

/// Accepts every Sparkle decision without showing UI.
final class SilentUserDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSLog("ArtWall: Sparkle error: \(error)")
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}
