// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Unzipper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CSArchive",
            path: "Sources/CSArchive",
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .target(
            name: "UnzipperCore",
            dependencies: ["CSArchive"],
            path: "Sources/UnzipperCore"
        ),
        .executableTarget(
            name: "Unzipper",
            dependencies: ["UnzipperCore"],
            path: "Sources/Unzipper"
        ),
        .testTarget(
            name: "UnzipperCoreTests",
            dependencies: ["UnzipperCore"],
            path: "Tests/UnzipperCoreTests"
        )
    ]
)
