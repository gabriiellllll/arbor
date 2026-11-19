// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackupKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BackupKit", targets: ["BackupKit"])],
    targets: [
        .target(name: "BackupKit"),
        .testTarget(name: "BackupKitTests", dependencies: ["BackupKit"]),
    ]
)
