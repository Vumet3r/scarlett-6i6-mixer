// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "scarlett-app",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "scarlett-app",
            path: "Sources/scarlett-app"
        )
    ]
)
