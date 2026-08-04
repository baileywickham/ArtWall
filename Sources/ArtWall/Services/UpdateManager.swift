import AppKit
import Sparkle

/// Fully-silent Sparkle updater. Checks daily, downloads and stages updates in
/// the background, and exposes `updateReady` so the popover can offer
/// "Restart to update" — a menu bar app rarely quits, so without that button a
/// staged update would wait indefinitely for the next relaunch.
@MainActor
@Observable
final class UpdateManager: NSObject {
    /// Outcome surface for a user-initiated check; the popover shows these as
    /// transient text where the version string normally sits.
    enum CheckStatus {
        case idle, checking, downloading, upToDate, failed
    }

    private(set) var updateReady = false
    private(set) var checkStatus: CheckStatus = .idle
    /// false in bare `swift build` runs, where there is no bundle to update
    /// and the popover keeps its plain version label.
    private(set) var active = false

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var driver: SilentUserDriver?
    @ObservationIgnored private var installNow: (() -> Void)?
    @ObservationIgnored private var userCheckInFlight = false
    @ObservationIgnored private var revertTask: Task<Void, Never>?

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
        // The driver's callbacks also fire for Sparkle's own scheduled daily
        // checks; finishUserCheck ignores those via userCheckInFlight, so the
        // status text only ever reacts to a click.
        driver.onUpdateFound = { [weak self] in
            Task { @MainActor in
                guard let self, self.userCheckInFlight else { return }
                self.checkStatus = .downloading
            }
        }
        driver.onUpdateNotFound = { [weak self] in
            Task { @MainActor in self?.finishUserCheck(.upToDate) }
        }
        driver.onError = { [weak self] in
            Task { @MainActor in self?.finishUserCheck(.failed) }
        }
        do {
            try updater.start()
            active = true
        } catch {
            NSLog("ArtWall: Sparkle failed to start: \(error)")
        }
    }

    func checkForUpdates() {
        guard let updater, !userCheckInFlight, !updateReady else { return }
        userCheckInFlight = true
        revertTask?.cancel()
        checkStatus = .checking
        updater.checkForUpdates()
    }

    private func finishUserCheck(_ status: CheckStatus) {
        guard userCheckInFlight else { return }
        userCheckInFlight = false
        checkStatus = status
        revertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.checkStatus = .idle
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
            // The "Restart to update" button replaces the status text.
            self.userCheckInFlight = false
            self.checkStatus = .idle
        }
        // Returning true stalls this and future update cycles until the staged update
        // installs (button click or app quit). Updates chain on next launch, so a
        // long-ignored button only delays, never loses, updates.
        return true
    }
}

/// Accepts every Sparkle decision without showing UI. The three outcome hooks
/// let UpdateManager surface user-initiated check results in the popover.
final class SilentUserDriver: NSObject, SPUUserDriver {
    var onUpdateFound: (() -> Void)?
    var onUpdateNotFound: (() -> Void)?
    var onError: (() -> Void)?

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        onUpdateFound?()
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        onUpdateNotFound?()
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSLog("ArtWall: Sparkle error: \(error)")
        onError?()
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
