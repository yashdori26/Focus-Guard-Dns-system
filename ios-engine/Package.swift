// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusDnsEngine",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FocusDnsEngine",
            targets: ["FocusDnsEngine"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FocusDnsEngine",
            dependencies: [],
            path: "Sources/FocusDnsEngine"
        ),
        .testTarget(
            name: "FocusDnsEngineTests",
            dependencies: ["FocusDnsEngine"],
            path: "Tests/FocusDnsEngineTests"
        ),
    ]
)
