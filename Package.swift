// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZaiTokenWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZaiTokenWidget",
            path: "Sources/ZaiTokenWidget"
        )
    ]
)
