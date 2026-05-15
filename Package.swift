// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Insomnia",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "InsomniaCore"),
        .executableTarget(
            name: "insomnia-hook",
            dependencies: ["InsomniaCore"]
        ),
        .executableTarget(
            name: "Insomnia",
            dependencies: ["InsomniaCore"]
        ),
        .testTarget(
            name: "InsomniaCoreTests",
            dependencies: ["InsomniaCore"]
        ),
    ]
)
