// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TaskSpool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TaskSpool",
            targets: ["TaskSpool"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TaskSpool",
            path: "Sources/TaskSpool"
        )
    ]
)
