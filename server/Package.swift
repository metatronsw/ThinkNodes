// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThinkNodes",
    platforms: [.macOS(.v13)],
    products: [
        // A szerver binárisa mindig kisbetűs: thinknodes.
        .executable(name: "thinknodes", targets: ["ThinkNodes"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.4"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.1"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.8.0"..<"5.0.0"),
        // Beépített LAN-tanúsítvány (HTTPS openssl nélkül).
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.18.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.6.0")
    ],
    targets: [
        // Táblázat doboz (docs/EXCEL.md): Vapor-független modul, a natív kliens is használhatja.
        .target(name: "ThinkTable"),
        // Kódszínezés (docs/node-types.md, code): Vapor-független modul; nyelvenként egy fájl.
        .target(name: "ThinkHighlight"),
        // Mag: munkalap-modell és tároló, renderelés, témák, prezentációk, csomagok. A modulhatáron átlátszó
        // deklarációk `package` láthatóságúak. Külön modul, hogy a szerverréteg módosításakor a release build
        // ne fordítsa újra (lásd README, „Szkriptek”).
        .target(
            name: "ThinkCore",
            dependencies: [
                "ThinkTable",
                "ThinkHighlight",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto")
            ]
        ),
        // Szerver: útvonalak, közös szerkesztés, linkelőnézet, indítás, LAN-tanúsítvány.
        .executableTarget(
            name: "ThinkNodes",
            dependencies: [
                "ThinkCore",
                "ThinkTable",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1")
            ]
        ),
        .testTarget(
            name: "ThinkNodesTests",
            dependencies: ["ThinkNodes", "ThinkCore", .product(name: "VaporTesting", package: "vapor")]
        ),
        .testTarget(name: "ThinkTableTests", dependencies: ["ThinkTable"]),
        .testTarget(name: "ThinkHighlightTests", dependencies: ["ThinkHighlight"])
    ]
)
