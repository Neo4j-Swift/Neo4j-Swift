// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Theo",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "Theo", targets: ["Theo"])
    ],
    dependencies: [
        .package(url: "https://github.com/Neo4j-Swift/Bolt-swift.git", exact: "6.0.3")
    ],
    targets: [
        .target(
            name: "Theo",
            dependencies: [.product(name: "Bolt", package: "Bolt-swift")]),
        .testTarget(
            name: "TheoTests",
            dependencies: ["Theo"],
            resources: [
                .copy("TheoBoltConfig.json"),
                .copy("TestFixtures")
            ])
    ]
)
