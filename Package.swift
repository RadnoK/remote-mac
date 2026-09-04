// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteMac",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "RemoteMacCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RemoteMac",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteMacCoreTests",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
