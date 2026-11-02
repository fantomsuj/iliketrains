// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ILikeTrainsData",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ILikeTrainsData", targets: ["ILikeTrainsData"])
    ],
    targets: [
        .target(
            name: "ILikeTrainsData",
            path: "I Like Trains",
            exclude: ["I_Like_TrainsApp.swift", "Resources", "Support", "Views"],
            sources: ["Models", "Services", "ViewModels"],
            resources: [.copy("Data/route-atlas.json")]
        ),
        .testTarget(
            name: "ILikeTrainsDataTests",
            dependencies: ["ILikeTrainsData"],
            path: "I Like TrainsTests"
        )
    ]
)
