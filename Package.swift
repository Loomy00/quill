// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Quill", targets: ["Quill"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1")
    ],
    targets: [
        .executableTarget(
            name: "Quill",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/Quill",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
