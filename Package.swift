// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevIsland",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "DevIsland"),
        .testTarget(name: "DevIslandTests", dependencies: ["DevIsland"])
    ]
)
