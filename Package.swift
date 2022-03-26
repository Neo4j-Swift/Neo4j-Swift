// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "Theo",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v12),
        .tvOS(.v12)
    ],
    products: [
        .library(name: "Theo", targets: ["Theo"])
    ],
    dependencies: [
        .package(name: "Bolt", url: "https://github.com/Neo4j-Swift/Bolt-swift.git", from: "5.2.0")
    ],
    targets: [
        .target(
            name: "Theo",
            dependencies: ["Bolt"]
            // , swiftSettings: [ .define("THEO_DEBUG") ]
        ),
        .testTarget(
            name: "TheoTests",
            dependencies: ["Theo"])
    ]
)
