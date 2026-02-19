// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        .package(url: "https://github.com/pointfreeco/swift-issue-reporting.git", from: .init(1, 8, 1)),
        .package(
            url: "https://github.com/JohnDemirci/ValueObservation.git",
            .upToNextMajor(from: "1.0.3")
        ),
    ],
    targets: [
        .target(
            name: "Supervision",
            dependencies: [
                .product(name: "IssueReporting", package: "swift-issue-reporting"),
                .product(name: "ValueObservation", package: "ValueObservation"),
            ],
        ),
        .testTarget(
            name: "SupervisionTests",
            dependencies: ["Supervision"]
        ),
    ]
)
