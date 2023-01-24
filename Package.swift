// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WatchConnectivitySwift",
    platforms: [
        .iOS(.v13),
        .watchOS(.v8)
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
            dependencies: [
            ]),
        .testTarget(
            name: "WatchConnectivitySwiftTests",
            dependencies: ["WatchConnectivitySwift"]),
    ],
    swiftLanguageVersions: [.v5]
)
