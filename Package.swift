// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Slate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Slate",
            targets: ["Slate"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Slate",
            path: "Sources"
        )
    ]
)
