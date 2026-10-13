// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UmamiBar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "UmamiBar", targets: ["UmamiBar"]),
        .library(name: "UmamiBarCore", targets: ["UmamiBarCore"]),
    ],
    targets: [
        .target(name: "UmamiBarCore"),
        .executableTarget(
            name: "UmamiBar",
            dependencies: ["UmamiBarCore"]
        ),
        .testTarget(
            name: "UmamiBarTests",
            dependencies: ["UmamiBarCore", "UmamiBar"]
        ),
    ]
)
