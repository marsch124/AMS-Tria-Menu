// swift-tools-version:5.9
import PackageDescription

// The rules of AMS Tria Menu that need no screen, so they can be tested in seconds.
let package = Package(
    name: "TriaMenuCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TriaMenuCore", targets: ["TriaMenuCore"])],
    targets: [
        .target(name: "TriaMenuCore"),
        .testTarget(name: "TriaMenuCoreTests", dependencies: ["TriaMenuCore"]),
    ]
)
