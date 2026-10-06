// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Henge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "Henge",
            targets: ["Henge"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Henge",
            path: "Sources"
        ),
        .testTarget(
            name: "HengeTests",
            dependencies: ["Henge"]
        ),
    ]
)
