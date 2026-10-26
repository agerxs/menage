// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Menage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Menage", targets: ["Menage"]),
    ],
    targets: [
        .target(name: "MenageCore"),
        .executableTarget(name: "Menage", dependencies: ["MenageCore"]),
        .testTarget(name: "MenageCoreTests", dependencies: ["MenageCore"]),
    ]
)
