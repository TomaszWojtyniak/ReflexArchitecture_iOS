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
        .library(name: "InventoryCore", targets: ["InventoryCore"]),
        .executable(name: "inventory-cli", targets: ["InventoryCLI"]),
    ],
    targets: [
        .target(name: "IntrospectionKit", swiftSettings: settings),
        .target(name: "InventoryCore", dependencies: ["IntrospectionKit"], swiftSettings: settings),
        .executableTarget(
            name: "InventoryCLI", dependencies: ["InventoryCore", "IntrospectionKit"], swiftSettings: settings),
        .testTarget(name: "IntrospectionKitTests", dependencies: ["IntrospectionKit"], swiftSettings: settings),
    ]
)
