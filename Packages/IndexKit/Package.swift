// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IndexKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IndexKit", targets: ["IndexKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
    ],
    targets: [
        .target(name: "IndexKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
    ]
)
