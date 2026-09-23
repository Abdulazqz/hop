// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(name: "Hop", dependencies: ["SwitcherCore"]),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"]),
    ]
)
