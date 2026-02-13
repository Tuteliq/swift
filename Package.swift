// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tuteliq",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "Tuteliq",
            targets: ["Tuteliq"]
        ),
    ],
    targets: [
        .target(
            name: "Tuteliq",
            dependencies: [],
            path: "Sources/Tuteliq"
        ),
        .testTarget(
            name: "TuteliqTests",
            dependencies: ["Tuteliq"],
            path: "Tests/TuteliqTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
