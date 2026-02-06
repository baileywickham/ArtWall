import Foundation

struct ArtPack: Codable, Identifiable {
    let id: Int
    let shortName: String
    let name: String
    let imageCount: Int
}

struct ArtImage: Codable, Identifiable {
    let id: String
    let packId: Int
    let index: Int
    let title: String
    let creator: String
    let year: String
    let attribution: String
    let imagePath: String?

    var hasImage: Bool { imagePath != nil }

    func resolvedURL(relativeTo base: URL) -> URL? {
        guard let imagePath else { return nil }
        return base.appending(path: imagePath)
    }
}

struct CatalogData: Codable {
    let packs: [ArtPack]
    let images: [ArtImage]
}
