import SwiftUI

struct SettingsView: View {
    @Environment(WallpaperState.self) private var state

    var body: some View {
        @Bindable var s = state
        Form {
            Toggle("Launch at login", isOn: $s.launchAtLogin)

            Toggle("Auto-rotate wallpaper", isOn: $s.autoRotateEnabled)

            Picker("Interval", selection: $s.rotateInterval) {
                ForEach(WallpaperState.intervals, id: \.1) { label, interval in
                    Text(label).tag(interval)
                }
            }
            .disabled(!state.autoRotateEnabled)
        }
        .formStyle(.grouped)
        .frame(width: 300)
    }
}
