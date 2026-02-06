import Foundation

@Observable
final class Catalog {
    var packs: [ArtPack] = []
    var images: [ArtImage] = []
    var dataDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: "workspace/ArtWall/Data")

    var imagesByPack: [Int: [ArtImage]] {
        Dictionary(grouping: images.filter(\.hasImage), by: \.packId)
    }

    var availablePacks: [ArtPack] {
        let packsWithImages = Set(imagesByPack.keys)
        return packs.filter { packsWithImages.contains($0.id) }
    }

    var allAvailableImages: [ArtImage] {
        images.filter(\.hasImage)
    }

    func load() {
        let catalogURL = dataDirectory.appending(path: "catalog.json")
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONDecoder().decode(CatalogData.self, from: data) else {
            print("Failed to load catalog.json from \(catalogURL.path())")
            return
        }
        self.packs = catalog.packs
        self.images = catalog.images
        print("Loaded \(packs.count) packs, \(allAvailableImages.count) images with files")
    }
}
