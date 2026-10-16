// swift-tools-version:5.9
// Platform-independent core of the Trains app: models, motion model, route geometry, wording.
// Builds and tests on macOS, iOS and Linux (`swift test`), so the logic is checked without Xcode.
import PackageDescription

let package = Package(
    name: "TrainsCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TrainsCore", targets: ["TrainsCore"])],
    targets: [
        .target(name: "TrainsCore"),
        .testTarget(name: "TrainsCoreTests", dependencies: ["TrainsCore"], resources: [.copy("Fixtures")]),
    ]
)
