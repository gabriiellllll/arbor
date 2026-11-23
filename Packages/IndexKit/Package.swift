// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IndexKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IndexKit", targets: ["IndexKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.21"),
    ],
    targets: [
        .target(name: "IndexKit", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        .testTarget(name: "IndexKitTests", dependencies: [
            "IndexKit", .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
    ]
)
