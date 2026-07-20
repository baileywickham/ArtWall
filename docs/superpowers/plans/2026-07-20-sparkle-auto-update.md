# Sparkle Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ArtWall silently auto-updates from GitHub Releases via Sparkle 2, with a "Restart to update" button in the popover for staged updates.

**Architecture:** Sparkle 2 SPM dependency drives scheduled background checks against an `appcast.xml` asset attached to each GitHub release (reached through the stable `releases/latest/download/` URL). A headless `SPUUserDriver` keeps it dialog-free; an `@Observable UpdateManager` replaces the hand-rolled `UpdateChecker`. `build.sh` embeds and signs `Sparkle.framework`; CI generates the EdDSA-signed appcast.

**Tech Stack:** Swift 5.10 SPM (no Xcode project), Sparkle 2.7.x, GitHub Actions (macos-15), `codesign`/`notarytool`.

## Global Constraints

- macOS 14+ (`platforms: [.macOS(.v14)]`), swift-tools-version 5.10.
- Sparkle is the ONLY external dependency; pin `from: "2.7.0"`.
- Local signing identity: `Developer ID Application: Usebits corp (Q9D9H424KQ)`.
- `build.sh` version-stamps by `sed "s/0.1.0/${VERSION}/g"` over Info.plist — new plist values must not contain the literal string `0.1.0`.
- The repo has no test targets; each task's gate is `swift build` plus the stated runtime verification. Task 5 is the end-to-end test and MUST pass before Task 6.
- App must remain runnable as a bare binary via `swift build` for dev (Sparkle disabled outside a `.app` bundle).
- The spec is `docs/superpowers/specs/2026-07-20-sparkle-auto-update-design.md`.

---

### Task 1: Add Sparkle dependency and rpath

**Files:**
- Modify: `Package.swift`

**Interfaces:**
- Produces: `import Sparkle` available to the target; app binary expects `Sparkle.framework` at `@executable_path/../Frameworks` when bundled.

- [ ] **Step 1: Replace Package.swift contents**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArtWall",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "ArtWall",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ArtWall",
            exclude: ["Info.plist", "Resources"],
            linkerSettings: [
                // Sparkle.framework is embedded at Contents/Frameworks by scripts/build.sh
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
```

- [ ] **Step 2: Resolve and build**

Run: `cd ~/workspace/ArtWall && swift build 2>&1 | tail -3`
Expected: `Build complete!` (first run also prints dependency fetch lines). If resolution fails on the version, run `swift package resolve` and check the highest 2.x tag with `git ls-remote --tags https://github.com/sparkle-project/Sparkle | grep -o 'refs/tags/2\.[0-9.]*$' | sort -V | tail -3`, then adjust `from:`.

- [ ] **Step 3: Confirm the binary artifact location (build.sh needs it in Task 4)**

Run: `find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*'`
Expected: one path like `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`

- [ ] **Step 4: Confirm the bare binary still launches (dev workflow)**

Run: `.build/debug/ArtWall & sleep 3; pgrep -x ArtWall && pkill -x ArtWall && echo OK`
Expected: `OK`. (Nothing imports Sparkle yet; this is the baseline. Re-checked after Task 3.)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "Add Sparkle 2 dependency with Frameworks rpath"
```

---

### Task 2: EdDSA keys, GitHub secret, and Info.plist Sparkle keys

**Files:**
- Modify: `Sources/ArtWall/Info.plist`

**Interfaces:**
- Produces: `SUPublicEDKey` (real key, from `generate_keys`) and `SUFeedURL` in Info.plist; repo secret `SPARKLE_PRIVATE_KEY` consumed by Task 6; Sparkle CLI tools left in the scratchpad for Task 5 (`sign_update`).

- [ ] **Step 1: Download the Sparkle distribution (CLI tools) to the scratchpad**

```bash
SCRATCH=/private/tmp/claude-501/-Users-baileywickham-workspace-ArtWall/45cbec8d-8108-40db-9674-9f797904cab9/scratchpad
curl -sL -o "$SCRATCH/sparkle.tar.xz" https://github.com/sparkle-project/Sparkle/releases/download/2.7.0/Sparkle-2.7.0.tar.xz
mkdir -p "$SCRATCH/sparkle" && tar -xf "$SCRATCH/sparkle.tar.xz" -C "$SCRATCH/sparkle"
ls "$SCRATCH/sparkle/bin/"
```
Expected: `generate_appcast generate_keys sign_update ...` (match the tarball version to whatever Task 1 resolved in Package.resolved).

- [ ] **Step 2: Generate the EdDSA keypair (stores private key in the login Keychain)**

Run: `"$SCRATCH/sparkle/bin/generate_keys"`
Expected: prints a base64 public key and says the private key was saved to the Keychain. Record the public key. If a key already exists, it prints the existing public key — use that.

- [ ] **Step 3: Set the CI secret**

```bash
"$SCRATCH/sparkle/bin/generate_keys" -x "$SCRATCH/sparkle_private_key"
gh secret set SPARKLE_PRIVATE_KEY --repo baileywickham/ArtWall < "$SCRATCH/sparkle_private_key"
rm -P "$SCRATCH/sparkle_private_key"
```
Expected: `✓ Set Actions secret SPARKLE_PRIVATE_KEY`. The exported file must be deleted after upload.

- [ ] **Step 4: Add Sparkle keys to Info.plist**

Insert before the closing `</dict>` of `Sources/ArtWall/Info.plist` (replace `PUBLIC_KEY_FROM_STEP_2` with the real key — this is a runtime-generated value, not a placeholder to leave in):

```xml
    <key>SUFeedURL</key>
    <string>https://github.com/baileywickham/ArtWall/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PUBLIC_KEY_FROM_STEP_2</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
```

- [ ] **Step 5: Validate the plist**

Run: `plutil -lint Sources/ArtWall/Info.plist`
Expected: `Sources/ArtWall/Info.plist: OK`

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtWall/Info.plist
git commit -m "Add Sparkle feed, public key, and automatic-update settings"
```

---

### Task 3: UpdateManager replaces UpdateChecker

**Files:**
- Create: `Sources/ArtWall/Services/UpdateManager.swift`
- Delete: `Sources/ArtWall/Services/UpdateChecker.swift`
- Modify: `Sources/ArtWall/App/AppDelegate.swift` (lines 10, 31, 36)
- Modify: `Sources/ArtWall/Views/MenuBarView.swift` (environment + bottom bar)

**Interfaces:**
- Consumes: Sparkle module from Task 1.
- Produces: `UpdateManager` (`@Observable`, `@MainActor`): `func start()`, `var updateReady: Bool { get }`, `func relaunchToUpdate()`. Injected via `.environment(updateManager)`.

- [ ] **Step 1: Write `Sources/ArtWall/Services/UpdateManager.swift`**

The `SPUUserDriver`/`SPUUpdaterDelegate` method names below are from Sparkle 2.7 and the compiler is the enforcement: if any signature mismatches, read the canonical ones from the artifact headers (`find .build/artifacts -name 'SPUUserDriver.h' -o -name 'SPUUpdaterDelegate.h' | xargs cat`) and adapt — keep behavior identical (auto-accept everything, no UI).

```swift
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
```

- [ ] **Step 2: Delete the old checker**

Run: `git rm Sources/ArtWall/Services/UpdateChecker.swift`

- [ ] **Step 3: Rewire AppDelegate**

In `Sources/ArtWall/App/AppDelegate.swift`:
- Line 10: `let updateChecker = UpdateChecker()` → `let updateManager = UpdateManager()`
- Line 31: `updateChecker.check()` → `updateManager.start()`
- Line 36: `.environment(updateChecker)` → `.environment(updateManager)`

- [ ] **Step 4: Rewire MenuBarView**

In `Sources/ArtWall/Views/MenuBarView.swift`:
- `@Environment(UpdateChecker.self) private var updateChecker` → `@Environment(UpdateManager.self) private var updateManager`
- In `bottomBar`, the version text and Update button swap for one slot (avoids re-crowding the 360-pt footer). Replace this block:

```swift
            Text(Self.versionString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            if updateChecker.updateAvailable {
                Button("Update") { updateChecker.openRelease() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
```

with:

```swift
            if updateManager.updateReady {
                Button("Restart to update") { updateManager.relaunchToUpdate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
            } else {
                Text(Self.versionString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
```

- [ ] **Step 5: Build and fix signature mismatches until clean**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. Compiler errors about `SPUUserDriver` conformance mean a signature drifted — fix from the artifact headers per Step 1's note.

- [ ] **Step 6: Bare-binary launch still works (Sparkle guarded off)**

Run: `.build/debug/ArtWall & sleep 3; pgrep -x ArtWall && pkill -x ArtWall && echo OK`
Expected: `OK`, no Sparkle crash (the `guard` in `start()` skips it). If dyld fails to find Sparkle at launch, SPM's artifact rpath isn't applied — note it and rely on bundled runs for dev, but record the limitation in CLAUDE.md.

- [ ] **Step 7: Commit**

```bash
git add -A Sources/ArtWall
git commit -m "Replace GitHub-polling UpdateChecker with silent Sparkle UpdateManager"
```

---

### Task 4: Embed and sign Sparkle.framework in build.sh

**Files:**
- Modify: `scripts/build.sh` (resource-copy section and the signing section)

**Interfaces:**
- Consumes: artifact path shape from Task 1 Step 3.
- Produces: `.build-app/ArtWall.app` containing `Contents/Frameworks/Sparkle.framework`, fully signed (both Developer ID and ad-hoc paths); DMG/ZIP as before.

- [ ] **Step 1: Add framework embedding after the resource copies**

Insert after the `cp Sources/ArtWall/Resources/MenuBarIcon@2x.png ...` line:

```bash
# Embed Sparkle.framework (SPM binary artifact) so the app can auto-update
SPARKLE_FRAMEWORK="$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*' | head -1)"
if [ -z "${SPARKLE_FRAMEWORK}" ]; then
    echo "ERROR: Sparkle.framework not found under .build/artifacts (run swift build -c release first)" >&2
    exit 1
fi
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
cp -R "${SPARKLE_FRAMEWORK}" "${APP_BUNDLE}/Contents/Frameworks/"
```

- [ ] **Step 2: Replace the signing section**

Replace the existing `if [ -n "${SIGN_IDENTITY}" ] ... fi` codesign block with:

```bash
# Sign inside-out: Sparkle's nested executables, then the framework, then the app.
# --preserve-metadata=entitlements keeps the XPC services' sandbox entitlements.
EMBEDDED_SPARKLE="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
sign_sparkle() {
    for nested in \
        "${EMBEDDED_SPARKLE}/Versions/B/XPCServices/Downloader.xpc" \
        "${EMBEDDED_SPARKLE}/Versions/B/XPCServices/Installer.xpc" \
        "${EMBEDDED_SPARKLE}/Versions/B/Autoupdate" \
        "${EMBEDDED_SPARKLE}/Versions/B/Updater.app"; do
        if [ -e "${nested}" ]; then
            codesign --force --preserve-metadata=entitlements "$@" "${nested}"
        fi
    done
    codesign --force "$@" "${EMBEDDED_SPARKLE}"
}

if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Code signing with identity: ${SIGN_IDENTITY}"
    sign_sparkle --options runtime --timestamp --sign "${SIGN_IDENTITY}"
    codesign --force --options runtime --timestamp --entitlements "${ENTITLEMENTS_FILE}" --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> CODESIGN_IDENTITY not set; using ad-hoc signature for local testing"
    sign_sparkle --sign -
    codesign --force --entitlements "${ENTITLEMENTS_FILE}" --sign - "${APP_BUNDLE}"
fi
```

- [ ] **Step 3: Build a signed local bundle and verify**

```bash
CODESIGN_IDENTITY="Developer ID Application: Usebits corp (Q9D9H424KQ)" ./scripts/build.sh 0.2.7
codesign --verify --deep --strict .build-app/ArtWall.app && echo SIGNATURE_OK
ls .build-app/ArtWall.app/Contents/Frameworks/Sparkle.framework/Versions/B
```
Expected: `SIGNATURE_OK`; listing shows `Autoupdate`, `Sparkle`, `Updater.app`, `XPCServices` (some entries may be absent in newer Sparkle — the loop tolerates that).

- [ ] **Step 4: Launch the bundle and confirm Sparkle starts without dialogs**

```bash
SCRATCH=/private/tmp/claude-501/-Users-baileywickham-workspace-ArtWall/45cbec8d-8108-40db-9674-9f797904cab9/scratchpad
ditto .build-app/ArtWall.app "$SCRATCH/ArtWall-tasktest.app"
open "$SCRATCH/ArtWall-tasktest.app" && sleep 5 && pgrep -x ArtWall && pkill -x ArtWall && echo OK
```
Expected: `OK`, no crash, no permission dialog (SUEnableAutomaticChecks pre-answers it). A feed fetch against the real URL may 404 (no appcast published yet) — that's fine and silent.

- [ ] **Step 5: Commit**

```bash
git add scripts/build.sh
git commit -m "Embed and sign Sparkle.framework in app bundle"
```

---

### Task 5: End-to-end local update test (verification gate — no code changes)

**Files:** none (scratchpad only). Uses `sign_update` from Task 2 Step 1 (a Sparkle 2.7.0 distribution extracted at `$SCRATCH/sparkle/`; re-download from `https://github.com/sparkle-project/Sparkle/releases/download/2.7.0/Sparkle-2.7.0.tar.xz` if missing).

**Interfaces:**
- Consumes: Task 4's signed bundle pipeline; Keychain EdDSA key from Task 2.

- [ ] **Step 1: Build two versions**

```bash
SCRATCH=/private/tmp/claude-501/-Users-baileywickham-workspace-ArtWall/45cbec8d-8108-40db-9674-9f797904cab9/scratchpad
mkdir -p "$SCRATCH/e2e/old"
CODESIGN_IDENTITY="Developer ID Application: Usebits corp (Q9D9H424KQ)" ./scripts/build.sh 0.2.7
ditto .build-app/ArtWall.app "$SCRATCH/e2e/old/ArtWall.app"
CODESIGN_IDENTITY="Developer ID Application: Usebits corp (Q9D9H424KQ)" ./scripts/build.sh 0.2.99
cp .build-app/ArtWall-0.2.99-macOS.zip "$SCRATCH/e2e/"
```

- [ ] **Step 2: Sign the update and write the appcast**

```bash
"$SCRATCH/sparkle/bin/sign_update" "$SCRATCH/e2e/ArtWall-0.2.99-macOS.zip"
```
Expected output like: `sparkle:edSignature="BASE64SIG" length="12345678"` — substitute both into `$SCRATCH/e2e/appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ArtWall</title>
    <item>
      <title>0.2.99</title>
      <sparkle:version>0.2.99</sparkle:version>
      <sparkle:shortVersionString>0.2.99</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="http://localhost:8123/ArtWall-0.2.99-macOS.zip"
                 sparkle:edSignature="BASE64SIG"
                 length="12345678"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

- [ ] **Step 3: Serve the feed and install the old version**

```bash
(cd "$SCRATCH/e2e" && python3 -m http.server 8123 > "$SCRATCH/e2e/http.log" 2>&1 &)
pkill -x ArtWall; sleep 1
rm -rf /Applications/ArtWall.app && ditto "$SCRATCH/e2e/old/ArtWall.app" /Applications/ArtWall.app
defaults write com.baileywickham.ArtWall SUFeedURL "http://localhost:8123/appcast.xml"
defaults delete com.baileywickham.ArtWall SULastCheckTime 2>/dev/null || true
open /Applications/ArtWall.app
```

- [ ] **Step 4: Watch the update happen**

Run: `sleep 90 && cat "$SCRATCH/e2e/http.log"`
Expected: GET lines for `appcast.xml` and `ArtWall-0.2.99-macOS.zip`. If the appcast is never fetched, check the unified log (dangerouslyDisableSandbox + full path per memory): `/usr/bin/log show --last 5m --predicate 'process == "ArtWall"' --level error`. An ATS block on the http URL would appear here — if so, temporarily test with `NSAllowsLocalNetworking` added to the *installed copy's* Info.plist (re-sign after editing), not the repo's.

- [ ] **Step 5: Verify the staged update and the popover button**

Open the popover (AX recipe: `click menu bar item 1 of menu bar 2` of process "ArtWall" via System Events; hold it open with `delay` and screenshot from a backgrounded `sleep N; screencapture -x`). Expected: bottom bar shows the "Restart to update" button instead of the version label. Click the button (AX: it is the button whose name is "Restart to update"). App relaunches.

- [ ] **Step 6: Confirm the new version is installed**

Run: `defaults read /Applications/ArtWall.app/Contents/Info.plist CFBundleShortVersionString`
Expected: `0.2.99`

- [ ] **Step 7: Clean up and restore**

```bash
defaults delete com.baileywickham.ArtWall SUFeedURL
defaults delete com.baileywickham.ArtWall SULastCheckTime 2>/dev/null || true
pkill -f 'http.server 8123'
pkill -x ArtWall; sleep 1
CODESIGN_IDENTITY="Developer ID Application: Usebits corp (Q9D9H424KQ)" ./scripts/build.sh 0.2.7
rm -rf /Applications/ArtWall.app && ditto .build-app/ArtWall.app /Applications/ArtWall.app
open /Applications/ArtWall.app
```
Expected: real 0.2.7 build back in /Applications and running. No commit (nothing changed).

---

### Task 6: Publish appcast from CI

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: repo secret `SPARKLE_PRIVATE_KEY` (Task 2), ZIP produced by `build.sh`.
- Produces: `appcast.xml` release asset — the target of `SUFeedURL` via `releases/latest/download/`.

- [ ] **Step 1: Add an appcast step between "Build, sign, and notarize" and "Create GitHub Release"**

```yaml
      - name: Generate Sparkle appcast
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          SPARKLE_VERSION=2.7.0
          curl -sL -o /tmp/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
          mkdir -p /tmp/sparkle && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle
          mkdir -p /tmp/appcast
          cp ".build-app/ArtWall-${{ steps.version.outputs.version }}-macOS.zip" /tmp/appcast/
          echo "$SPARKLE_PRIVATE_KEY" | /tmp/sparkle/bin/generate_appcast \
            --ed-key-file - \
            --download-url-prefix "https://github.com/baileywickham/ArtWall/releases/download/v${{ steps.version.outputs.version }}/" \
            /tmp/appcast
          cp /tmp/appcast/appcast.xml .build-app/appcast.xml
```

(Keep `SPARKLE_VERSION` in sync with Package.resolved when bumping the dependency.)

- [ ] **Step 2: Add the asset to the release step's files list**

```yaml
          files: |
            .build-app/ArtWall-${{ steps.version.outputs.version }}-macOS.dmg
            .build-app/ArtWall-${{ steps.version.outputs.version }}-macOS.zip
            .build-app/appcast.xml
```

- [ ] **Step 3: Lint the workflow**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"`
Expected: `YAML OK`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Generate and publish Sparkle appcast on release"
```

---

### Task 7: Docs and wrap-up

**Files:**
- Modify: `CLAUDE.md` (Architecture > Services bullet for `UpdateChecker` → `UpdateManager`; release workflow sentence)

**Interfaces:** none.

- [ ] **Step 1: Update CLAUDE.md**

Replace the `UpdateChecker` bullet under Services with:

```markdown
  - `UpdateManager` — Sparkle 2 wrapper (silent auto-updates from GitHub release appcast; "Restart to update" appears in the popover when an update is staged). Only active when running from a .app bundle.
```

And append to the Build & Run section:

```markdown
Releases also publish `appcast.xml`; Sparkle clients read it via
`https://github.com/baileywickham/ArtWall/releases/latest/download/appcast.xml`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document Sparkle auto-update in CLAUDE.md"
```

- [ ] **Step 3: Report** — first real-world exercise happens on the next tagged release (v0.2.8): CI must pass notarization with the embedded framework, and the release must contain `appcast.xml`. Flag this to Bailey as the remaining unverified step.
