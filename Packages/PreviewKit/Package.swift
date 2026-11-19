// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PreviewKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PreviewKit", targets: ["PreviewKit"])],
    targets: [
        .target(name: "PreviewKit"),
        .testTarget(name: "PreviewKitTests", dependencies: ["PreviewKit"]),
    ]
)
