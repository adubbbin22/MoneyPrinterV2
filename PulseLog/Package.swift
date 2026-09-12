// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PulseLogSignal",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "PulseLogSignal", targets: ["PulseLogSignal"]),
    ],
    targets: [
        // Deliberately free of Apple-framework dependencies: the estimator is
        // the part that must be testable on any machine, including CI without
        // a simulator. The camera layer depends on this, never the reverse.
        .target(name: "PulseLogSignal"),
        .testTarget(
            name: "PulseLogSignalTests",
            dependencies: ["PulseLogSignal"],
            resources: [.copy("Resources/ppg_vectors.json")]
        ),
    ]
)
