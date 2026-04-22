// swift-tools-version: 6.2

import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableExperimentalFeature("IsolatedAny"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("FullTypedThrows"),
]

let package = Package(
    name: "AnkiBridge",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AnkiKit", targets: ["AnkiKit"]),
        .library(name: "AnkiProto", targets: ["AnkiProto"]),
        .library(name: "AnkiBackend", targets: ["AnkiBackend"]),
        .library(name: "AnkiClients", targets: ["AnkiClients"]),
        .library(name: "AnkiSync", targets: ["AnkiSync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/Manhhao/hoshidicts.git", branch: "main"),
    ],
    targets: [
        // MARK: - Rust Bridge
        .binaryTarget(
            name: "AnkiRustLib",
            path: "AnkiRust.xcframework"
        ),
        .target(
            name: "AnkiProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiBackend",
            dependencies: [
                "AnkiRustLib",
                "AnkiProto",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        // MARK: - Libraries
        .target(
            name: "AnkiKit",
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiClients",
            dependencies: [
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                "AnkiSync",
                .product(name: "CHoshiDicts", package: "hoshidicts"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: sharedSwiftSettings + [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .target(
            name: "AnkiSync",
            dependencies: [
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "AnkiSyncTests",
            dependencies: [
                "AnkiSync",
                "AnkiKit",
            ],
            path: "Sources/AnkiSyncTests",
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
