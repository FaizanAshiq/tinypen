// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tinypen",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TinypenCore"),
        .executableTarget(name: "TinypenApp", dependencies: ["TinypenCore"]),
        .testTarget(name: "TinypenCoreTests", dependencies: ["TinypenCore"]),
    ]
)
