// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decant",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DecantCore"),
        .executableTarget(name: "Decant", dependencies: ["DecantCore"]),
        .testTarget(name: "DecantCoreTests", dependencies: ["DecantCore"]),
    ]
)
