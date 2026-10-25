// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LightCodes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LightCodes",
            path: "Sources/LightCodes"
        )
    ]
)
