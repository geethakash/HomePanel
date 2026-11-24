// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HAKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HAKit", targets: ["HAKit"]),
    ],
    targets: [
        .target(name: "HAKit"),
        .testTarget(name: "HAKitTests", dependencies: ["HAKit"]),
    ]
)
