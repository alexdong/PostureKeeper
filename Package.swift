// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PostureKeeper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "PostureKeeper",
            targets: ["PostureKeeper"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "PostureKeeper",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)