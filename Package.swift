// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BobcatBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "BobcatBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/BobcatBar",
            // build.sh puts Sparkle.framework in Contents/Frameworks
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "BobcatBarTests", dependencies: ["BobcatBar"], path: "Tests/BobcatBarTests",
                    exclude: ["Fixtures"]),
    ]
)
