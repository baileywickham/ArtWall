import SwiftUI

struct CurrentWallpaperView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(WallpaperState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            if let image = state.currentImage {
                imagePreview(image)
                metadata(image)
            } else {
                Spacer()
                Text("No wallpaper set")
                    .foregroundStyle(.secondary)
                Text("Tap \"Random\" to get started")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            Text("Rotating: \(state.selectionLabel) (\(state.rotatePool.count) images)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let image = state.currentImage {
                    Button {
                        state.dislike(image)
                    } label: {
                        Image(systemName: "hand.thumbsdown")
                    }
                    .buttonStyle(.bordered)
                    .help("Skip this image in future rotations")
                }
                Button("Random") { state.setRandom() }
                    .buttonStyle(.borderedProminent)
                Button("Next") { state.setNext() }
                    .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imagePreview(_ artImage: ArtImage) -> some View {
        Group {
            if let url = artImage.resolvedURL(relativeTo: catalog.dataDirectory),
               let nsImage = ImageLoader.shared.thumbnail(for: url, maxPixels: 600) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 4)
            }
        }
        .padding(.top, 8)
    }

    private func metadata(_ image: ArtImage) -> some View {
        VStack(spacing: 4) {
            Text(image.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(image.creator)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !image.year.isEmpty {
                Text(image.year)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !image.attribution.isEmpty {
                Text(image.attribution)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
