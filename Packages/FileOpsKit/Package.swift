// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileOpsKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FileOpsKit", targets: ["FileOpsKit"])],
    targets: [
        .target(name: "FileOpsKit"),
        .testTarget(name: "FileOpsKitTests", dependencies: ["FileOpsKit"]),
    ]
)
