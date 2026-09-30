// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiFiLensCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WiFiLensCore", targets: ["WiFiLensCore"]),
    ],
    targets: [
        .target(name: "WiFiLensCore"),
        .testTarget(name: "WiFiLensCoreTests", dependencies: ["WiFiLensCore"]),
    ],
    swiftLanguageModes: [.v6]
)
