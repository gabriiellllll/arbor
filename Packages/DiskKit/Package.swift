// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DiskKit", targets: ["DiskKit"])],
    targets: [
        .target(name: "DiskKit"),
        .testTarget(name: "DiskKitTests", dependencies: ["DiskKit"]),
    ]
)
