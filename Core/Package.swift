// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "InventoryCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "IntrospectionKit", targets: ["IntrospectionKit"]),
    ],
    targets: [
        .target(name: "IntrospectionKit", swiftSettings: settings),
        .testTarget(name: "IntrospectionKitTests", dependencies: ["IntrospectionKit"], swiftSettings: settings),
    ]
)
