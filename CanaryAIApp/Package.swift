// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CanaryAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CanaryAI",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        ),
    ]
)
