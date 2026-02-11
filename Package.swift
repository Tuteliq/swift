// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SafeNest",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SafeNest",
            targets: ["SafeNest"]
        ),
    ],
    targets: [
        .target(
            name: "SafeNest",
            dependencies: [],
            path: "Sources/SafeNest"
        ),
        .testTarget(
            name: "SafeNestTests",
            dependencies: ["SafeNest"],
            path: "Tests/SafeNestTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
