// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThinkNodes",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.4"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ThinkNodes",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "cmark-gfm", package: "swift-cmark")
            ]
        ),
        .testTarget(
            name: "ThinkNodesTests",
            dependencies: ["ThinkNodes", .product(name: "VaporTesting", package: "vapor")]
        )
    ]
)
