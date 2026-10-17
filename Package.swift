// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decant",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DecantCore"),
        .executableTarget(
            name: "Decant",
            dependencies: ["DecantCore"],
            resources: [.copy("Resources/AppIcon.icns")],  // regenerate with Assets/make-icon.sh
            // SwiftPM records the deployment target as the SDK version, which makes AppKit fall back to the
            // pre-macOS 26 look. Record the real SDK so the system Liquid Glass design is used.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "14.0", "-Xlinker", "26.0"])]
        ),
        .testTarget(name: "DecantCoreTests", dependencies: ["DecantCore"]),
    ]
)
