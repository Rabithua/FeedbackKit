// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeedbackKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "FeedbackKitCore", targets: ["FeedbackKitCore"]),
        .library(name: "FeedbackKitDiagnostics", targets: ["FeedbackKitDiagnostics"]),
        .library(name: "FeedbackKitUI", targets: ["FeedbackKitUI"]),
        .library(name: "FeedbackKitTestSupport", targets: ["FeedbackKitTestSupport"]),
    ],
    targets: [
        .target(name: "FeedbackKitCore"),
        .target(
            name: "FeedbackKitDiagnostics",
            dependencies: ["FeedbackKitCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "FeedbackKitUI",
            dependencies: ["FeedbackKitCore", "FeedbackKitDiagnostics"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "FeedbackKitTestSupport",
            dependencies: ["FeedbackKitCore", "FeedbackKitDiagnostics"]
        ),
        .testTarget(name: "FeedbackKitCoreTests", dependencies: ["FeedbackKitCore", "FeedbackKitTestSupport"]),
        .testTarget(name: "FeedbackKitDiagnosticsTests", dependencies: ["FeedbackKitDiagnostics"]),
    ],
    swiftLanguageModes: [.v6]
)
