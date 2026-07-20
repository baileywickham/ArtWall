// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArtWall",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "ArtWall",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ArtWall",
            exclude: ["Info.plist", "Resources"],
            linkerSettings: [
                // Sparkle.framework is embedded at Contents/Frameworks by scripts/build.sh
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
