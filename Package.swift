// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OsmoActionViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OsmoActionViewer", targets: ["OsmoActionViewer"])
    ],
    targets: [
        .executableTarget(name: "OsmoActionViewer")
    ]
)
