// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CanvasKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CanvasKit", targets: ["CanvasKit"])],
    targets: [
        .target(name: "CanvasKit"),
        .testTarget(name: "CanvasKitTests", dependencies: ["CanvasKit"]),
    ]
)
