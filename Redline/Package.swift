// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Kept at 6.0 so the Xcode on GitHub's macOS runners can build it.

import PackageDescription

let package = Package(
    name: "RedlineCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RedlineCore", targets: ["RedlineCore"])
    ],
    targets: [
        // Platform-independent logic lives here so it builds and tests on Windows too.
        // The SwiftUI app itself lives in ../App and is only built on macOS (see ../project.yml).
        .target(
            name: "RedlineCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "RedlineCoreTests",
            dependencies: ["RedlineCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        )
    ]
)
