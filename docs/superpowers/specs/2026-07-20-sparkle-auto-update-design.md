# Sparkle Auto-Update — Design

Date: 2026-07-20
Status: approved (Bailey, in-session)

## Goal

ArtWall updates itself fully automatically: it checks for new GitHub releases in the
background, downloads and stages them silently, and applies them without prompts. No
manual DMG downloads. Approach chosen: Sparkle 2 (over a hand-rolled updater or
Homebrew/launchd upgrades).

## UX decisions

- **Fully automatic**: no dialogs, no first-launch "check automatically?" prompt.
- Because a menu bar app rarely quits (Sparkle normally applies staged updates on
  quit), the popover's existing "Update" button slot becomes a **"Restart to update"**
  button that appears only when an update is downloaded and staged; clicking it
  relaunches into the new version.
- The `version · commit` label in the popover footer stays.

## Components

### 1. App (Swift)

- `Package.swift`: add `sparkle-project/Sparkle` (from: 2.x), link the `Sparkle`
  product; add rpath linker setting `@executable_path/../Frameworks`.
- `Info.plist` keys: `SUFeedURL` (see feed below), `SUPublicEDKey`,
  `SUEnableAutomaticChecks` = true, `SUAutomaticallyUpdate` = true,
  `SUScheduledCheckInterval` = 86400.
- New `Services/UpdateManager.swift`: `@Observable` wrapper owning an `SPUUpdater`
  (headless user driver, no standard Sparkle UI). Implements `SPUUpdaterDelegate` to
  observe "update staged for install on quit" and exposes `updateReady: Bool` +
  `relaunchToUpdate()`.
- Delete `Services/UpdateChecker.swift` (GitHub API poller); rewire `MenuBarView` to
  `UpdateManager`.

### 2. Feed + signing

- One-time: run Sparkle `generate_keys`. Public key → `SUPublicEDKey` in Info.plist.
  Private key → repo secret `SPARKLE_PRIVATE_KEY` (and Bailey's local Keychain).
- Appcast hosting without extra infrastructure: every release uploads an
  `appcast.xml` asset describing that release; `SUFeedURL` =
  `https://github.com/baileywickham/ArtWall/releases/latest/download/appcast.xml`,
  which always redirects to the newest release's copy.
- Sparkle installs from the ZIP asset the release pipeline already produces.

### 3. Build plumbing

- `scripts/build.sh`: copy `Sparkle.framework` (from `.build/artifacts/...`) into
  `Contents/Frameworks/`; sign inside-out for notarization — Sparkle's nested
  XPC services, `Autoupdate`, and `Updater.app` first (hardened runtime), then the
  framework, then the app bundle.
- `.github/workflows/release.yml`: new step after the ZIP is built — run Sparkle's
  `generate_appcast` with `SPARKLE_PRIVATE_KEY`, point download URLs at the release's
  asset URL, upload `appcast.xml` with the other assets.

## Error handling

- Update check/download failures are non-fatal; Sparkle retries on the next
  scheduled cycle and logs to the unified log.
- CI fails loudly if appcast generation or signing fails (no release without a feed).

## Verification

- Local end-to-end before CI: install a Sparkle-enabled build with the feed
  overridden (`defaults write com.baileywickham.ArtWall SUFeedURL <localhost URL>`)
  serving a fake higher-version appcast + EdDSA-signed ZIP; confirm silent download,
  staging, and version swap after relaunch. Restore the override afterwards.
- Confirm dev workflow intact: `swift build` and running the bare binary still work.
- Notarization of the Sparkle-embedded bundle verified on the next tagged release.

## Out of scope / notes

- No "Check for updates" menu item (YAGNI; can add later).
- Existing installs (≤0.2.7) have no Sparkle: one final manual update is expected.
- Homebrew tap unaffected; cask may later gain `auto_updates true`.
