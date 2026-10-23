// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HearthKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HearthKit", targets: ["HearthKit"]),
    ],
    targets: [
        // Pure, UI-free logic ported from the Android app: the Home Assistant client,
        // the Car model + parsing, and the Car Beacon view-model. Builds and unit-tests
        // on macOS via `swift test` (no iOS Simulator runtime required).
        .target(name: "HearthKit"),
        .testTarget(name: "HearthKitTests", dependencies: ["HearthKit"]),
    ]
)
