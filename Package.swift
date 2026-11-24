// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThinkNodes",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.4"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.1"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.8.0"..<"5.0.0")
    ],
    targets: [
        // Táblázat doboz (EXCEL.md): Vapor-független modul, a natív kliens is használhatja.
        .target(name: "ThinkTable"),
        .executableTarget(
            name: "ThinkNodes",
            dependencies: [
                "ThinkTable",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "ThinkNodesTests",
            dependencies: ["ThinkNodes", .product(name: "VaporTesting", package: "vapor")]
        ),
        .testTarget(name: "ThinkTableTests", dependencies: ["ThinkTable"])
    ]
)
