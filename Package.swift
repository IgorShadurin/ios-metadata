// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetadataCoreKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MetadataCore", targets: ["MetadataCore"])
    ],
    targets: [
        .target(
            name: "MetadataCore",
            path: "AwesomeApp/MetadataCore"
        ),
        .testTarget(
            name: "MetadataCoreTests",
            dependencies: ["MetadataCore"],
            path: "MetadataCoreTests"
        )
    ]
)
