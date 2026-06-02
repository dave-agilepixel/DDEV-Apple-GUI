// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DDEVUI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "DDEVUI", targets: ["DDEVUIApp"])
    ],
    targets: [
        .executableTarget(
            name: "DDEVUIApp",
            path: "Sources/DDEVUIApp"
        ),
        .testTarget(
            name: "DDEVUIAppTests",
            dependencies: ["DDEVUIApp"],
            path: "Tests/DDEVUIAppTests",
            resources: [.copy("Fixtures/ddev-start-output.txt")]
        )
    ]
)
