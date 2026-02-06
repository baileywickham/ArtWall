import SwiftUI

struct MenuBarView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(WallpaperState.self) private var state
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
        return HStack(spacing: 8) {
            Toggle("Rotate", isOn: $s.autoRotateEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
            Picker("", selection: $s.rotateInterval) {
                ForEach(WallpaperState.intervals, id: \.1) { label, interval in
                    Text(label).tag(interval)
                }
            }
            .controlSize(.small)
            .frame(width: 90)
            .disabled(!state.autoRotateEnabled)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
