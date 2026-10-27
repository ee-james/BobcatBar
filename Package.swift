// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BobcatBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BobcatBar",
            path: "Sources/BobcatBar"
        )
    ]
)
