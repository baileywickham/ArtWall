import SwiftUI

struct MenuBarView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(WallpaperState.self) private var state
    @Environment(UpdateChecker.self) private var updateChecker
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Current").tag(0)
                Text("Browse").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            if selectedTab == 0 {
                CurrentWallpaperView()
            } else {
                BrowseView()
            }

            Divider()

            bottomBar
        }
        .frame(width: 360, height: 480)
        .onAppear { state.restoreCurrent() }
    }

    private var bottomBar: some View {
        @Bindable var s = state
        return HStack(spacing: 6) {
            Toggle("Rotate", isOn: $s.autoRotateEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
            Picker("", selection: $s.rotateInterval) {
                ForEach(WallpaperState.intervals, id: \.1) { label, interval in
                    Text(label).tag(interval)
                }
            }
            .controlSize(.small)
            .frame(width: 84)
            .disabled(!state.autoRotateEnabled)
            Spacer(minLength: 4)
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
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // "0.2.7 · af5f52b", with "*" marking a build from a dirty working tree
    private static let versionString: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        if let commit = Bundle.main.object(forInfoDictionaryKey: "ArtWallGitCommit") as? String {
            return "\(version) · \(commit.replacingOccurrences(of: "-dirty", with: "*"))"
        }
        return version
    }()
}
