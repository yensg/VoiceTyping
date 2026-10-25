// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalDictation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
        .executable(name: "LocalDictation", targets: ["LocalDictation"])
    ],
    targets: [
        .target(name: "DictationCore"),
        .target(name: "DictationUI"),
        .executableTarget(name: "LocalDictation", dependencies: ["DictationCore", "DictationUI"]),
        .executableTarget(name: "WorkerChecks", dependencies: ["DictationCore"], path: "Tests/WorkerChecks"),
        .executableTarget(name: "InterfaceChecks", dependencies: ["DictationUI"], path: "Tests/InterfaceChecks"),
        .executableTarget(name: "OverlayChecks", dependencies: ["DictationUI"], path: "Tests/OverlayChecks"),
        .executableTarget(name: "PolicyChecks", dependencies: ["DictationCore"], path: "Tests/DictationCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
