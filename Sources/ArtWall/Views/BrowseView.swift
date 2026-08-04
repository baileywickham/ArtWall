import SwiftUI

private enum BrowseSelection: Hashable {
    case pack(Int)
    case liked
}

struct BrowseView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(WallpaperState.self) private var state
    @State private var selection: BrowseSelection?

    var body: some View {
        switch selection {
        case .pack(let packId):
            grid(
                title: catalog.packs.first(where: { $0.id == packId })?.shortName ?? "",
                images: catalog.imagesByPack[packId] ?? []
            )
        case .liked:
            grid(title: "Liked", images: state.likedImages)
        case nil:
            packList
        }
    }

    private var packList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Select All row
                Button {
                    state.selectAll()
                } label: {
                    HStack {
                        Image(systemName: state.isAllSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(state.isAllSelected ? .blue : .gray)
                            .font(.body)
                        Text("All galleries")
                            .font(.headline)
                        Spacer()
                        let count = catalog.allAvailableImages.count
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 16)

                likedRow

                Divider().padding(.horizontal, 16)

                ForEach(catalog.availablePacks) { pack in
                    HStack(spacing: 0) {
                        // Checkbox area
                        Button {
                            state.togglePack(pack.id)
                        } label: {
                            let selected = state.selectedPackIds.contains(pack.id)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected ? .blue : .gray)
                                .font(.body)
                                .frame(width: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Row tap -> drill into grid
                        Button {
                            selection = .pack(pack.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pack.shortName)
                                        .font(.headline)
                                    Text(pack.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                let count = catalog.imagesByPack[pack.id]?.count ?? 0
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var likedRow: some View {
        HStack(spacing: 0) {
            // Checkbox area
            Button {
                state.toggleLikedSelection()
            } label: {
                Image(systemName: state.likedSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(state.likedSelected ? .blue : .gray)
                    .font(.body)
                    .frame(width: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Row tap -> drill into grid
            Button {
                selection = .liked
            } label: {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                        .font(.body)
                    Text("Liked")
                        .font(.headline)
                    Spacer()
                    Text("\(state.likedImages.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func grid(title: String, images: [ArtImage]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    selection = nil
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Packs")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Color.clear.frame(width: 44)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            if images.isEmpty {
                Spacer()
                Text("No liked images yet")
                    .foregroundStyle(.secondary)
                Text("Tap \(Image(systemName: "hand.thumbsup")) on a wallpaper you love")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(images) { image in
                            ThumbnailCell(
                                image: image,
                                dataDir: catalog.dataDirectory,
                                action: { state.setWallpaper(image) },
                                onUnlike: selection == .liked ? { state.unlike(image) } : nil
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct ThumbnailCell: View {
    let image: ArtImage
    let dataDir: URL
    let action: () -> Void
    var onUnlike: (() -> Void)?
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.black.opacity(0.05)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(image.title)
        .contextMenu {
            if let onUnlike {
                Button("Remove from Liked", action: onUnlike)
            }
        }
        .task(id: image.id) {
            if let url = image.resolvedURL(relativeTo: dataDir) {
                thumbnail = await Task.detached {
                    ImageLoader.shared.thumbnail(for: url, maxPixels: 200)
                }.value
            }
        }
    }
}
