// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AutoPauseCemu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "auto-pause-cemu", targets: ["AutoPauseCemu"]),
        .library(name: "AutoPauseCore", targets: ["AutoPauseCore"]),
    ],
    targets: [
        .target(name: "AutoPauseCore"),
        .executableTarget(
            name: "AutoPauseCemu",
            dependencies: ["AutoPauseCore"]
        ),
        .testTarget(
            name: "AutoPauseCoreTests",
            dependencies: ["AutoPauseCore"]
        ),
    ]
)
