// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "iManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "iManager",
            path: "Sources/iManager"
        )
    ]
)
