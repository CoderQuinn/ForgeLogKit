// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForgeLogKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(name: "ForgeLogKit", targets: ["ForgeLogKit"]),
        .library(name: "ForgeLogKitOC", targets: ["ForgeLogKitOC"]),
        .library(name: "ForgeLogKitC", targets: ["ForgeLogKitC"]),
    ],
    targets: [
        // C base
        .target(
            name: "ForgeLogKitC",
            path: "Sources/ForgeLogKitC",
            publicHeadersPath: "."
        ),

        // ObjC adapter (this is the key)
        .target(
            name: "ForgeLogKitOC",
            dependencies: ["ForgeLogKitC"],
            path: "Sources/ForgeLogKitOC",
            publicHeadersPath: "."
        ),

        // Swift API
        .target(
            name: "ForgeLogKit",
            dependencies: ["ForgeLogKitC"],
            path: "Sources/ForgeLogKit"
        ),

        .target(
            name: "ForgeLogKitCTestSupport",
            dependencies: ["ForgeLogKitC"],
            path: "Tests/ForgeLogKitCTestSupport",
            publicHeadersPath: "."
        ),

        .testTarget(
            name: "ForgeLogKitTests",
            dependencies: [
                "ForgeLogKit",
                "ForgeLogKitC",
                "ForgeLogKitCTestSupport",
                "ForgeLogKitOC",
            ],
            path: "Tests/ForgeLogKitTests"
        ),
    ]
)
