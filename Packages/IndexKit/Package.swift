// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IndexKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IndexKit", targets: ["IndexKit"])],
    targets: [
        .target(name: "IndexKit"),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
    ]
)
