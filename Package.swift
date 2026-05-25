// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Supervision",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(
            name: "Supervision",
            targets: ["Supervision"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/xctest-dynamic-overlay",
            from: "1.8.1"
        ),
        .package(
            url: "https://github.com/JohnDemirci/ValueObservation.git",
            .upToNextMajor(from: "1.0.3")
        ),
    ],
    targets: [
        .target(
            name: "Supervision",
            dependencies: [
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "ValueObservation", package: "ValueObservation"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("LifetimeDependence"),
                .enableExperimentalFeature("Lifetimes"),
            ]
        ),
        .testTarget(
            name: "SupervisionTests",
            dependencies: ["Supervision"]
        ),
    ]
)
