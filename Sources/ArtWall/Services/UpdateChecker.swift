import AppKit

@Observable
final class UpdateChecker {
    var updateAvailable = false
    var latestVersion: String?
    var releaseURL: URL?

    private let currentVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }()

    private static let releasesURL = URL(string: "https://api.github.com/repos/baileywickham/ArtWall/releases/latest")!

    func check() {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: Self.releasesURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let url = URL(string: htmlURL) else { return }

            let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            await MainActor.run {
                self.latestVersion = remote
                self.releaseURL = url
                self.updateAvailable = remote.compare(currentVersion, options: .numeric) == .orderedDescending
            }
        }
    }

    func openRelease() {
        guard let url = releaseURL else { return }
        NSWorkspace.shared.open(url)
    }
}
