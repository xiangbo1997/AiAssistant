// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BuBuAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BuBuAssistant", targets: ["BuBuAssistant"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2")
    ],
    targets: [
        .executableTarget(
            name: "BuBuAssistant",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "BuBuAssistant"
        )
    ]
)
