// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteMac",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .target(
            name: "RemoteMacCore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RemoteMac",
            dependencies: [
                "RemoteMacCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteMacCoreTests",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteMacTests",
            dependencies: ["RemoteMac"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
