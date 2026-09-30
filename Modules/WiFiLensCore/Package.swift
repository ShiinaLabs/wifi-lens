// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiFiLensCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WiFiLensCore", targets: ["WiFiLensCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ShiinaLabs/chart-lens.git", revision: "e2e00e5253a51e7031d30cf41015ff146cd9a886"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
        .package(url: "https://github.com/apple/swift-log", from: "1.15.1"),
        .package(url: "https://github.com/ShiinaLabs/SplitView.git", revision: "ed017042512b9b6a508b240b12eab675c2412aea"),
        .package(url: "https://github.com/ShiinaLabs/MarkdownKit.git", revision: "f399a6674d6efb5a7d9b2f1dfb8e1e6504f3bba2"),
    ],
    targets: [
        .target(
            name: "WiFiLensCore",
            dependencies: [
                .product(name: "ChartLens", package: "chart-lens"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SplitView", package: "splitview"),
                .product(name: "MarkdownKit", package: "markdownkit"),
            ],
            resources: [.process("Spectrum/SpectrumHeatmap.metal")]
        ),
        .testTarget(
            name: "WiFiLensCoreTests",
            dependencies: ["WiFiLensCore", .product(name: "ChartLens", package: "chart-lens"), .product(name: "MCP", package: "swift-sdk")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
