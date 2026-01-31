// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WatchConnectivitySwift",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "WatchConnectivitySwift",
            targets: ["WatchConnectivitySwift"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "WatchConnectivitySwift",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WatchConnectivitySwiftTests",
            dependencies: ["WatchConnectivitySwift"]),
    ]
)
