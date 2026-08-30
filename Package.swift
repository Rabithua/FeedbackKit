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
        .library(name: "FeedbackKitJourney", targets: ["FeedbackKitJourney"]),
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
            name: "FeedbackKitJourney",
            dependencies: ["FeedbackKitCore"]
        ),
        .target(
            name: "FeedbackKitUI",
            dependencies: ["FeedbackKitCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "FeedbackKitTestSupport",
            dependencies: ["FeedbackKitCore", "FeedbackKitDiagnostics"]
        ),
        .testTarget(name: "FeedbackKitCoreTests", dependencies: ["FeedbackKitCore", "FeedbackKitTestSupport"]),
        .testTarget(name: "FeedbackKitDiagnosticsTests", dependencies: ["FeedbackKitDiagnostics"]),
        .testTarget(
            name: "FeedbackKitJourneyTests",
            dependencies: ["FeedbackKitJourney", "FeedbackKitCore", "FeedbackKitTestSupport"]
        ),
        .testTarget(
            name: "FeedbackKitUITests",
            dependencies: ["FeedbackKitUI", "FeedbackKitCore", "FeedbackKitTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
