// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArtWall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ArtWall",
            path: "Sources/ArtWall"
        )
    ]
)
