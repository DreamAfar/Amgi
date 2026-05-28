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
        .library(name: "AnkiServices", targets: ["AnkiServices"]),
        .library(name: "AnkiSync", targets: ["AnkiSync"]),
        .library(name: "AmgiCardWeb", targets: ["AmgiCardWeb"]),
    ],
    dependencies: [
        .package(path: "AmgiDomain"),
        .package(path: "AmgiUI"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(path: "Libraries/EPUBKit"),
    ],
    targets: [
        // MARK: - Rust Bridge
        .binaryTarget(
            name: "AnkiRustLib",
            path: "AnkiRustLib.xcframework"
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
            exclude: [
                "ReaderTypes.swift",
                "DictionaryTypes.swift",
                "AppDictionaryTypes.swift",
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiClients",
            dependencies: [
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                "AnkiServices",
                "AnkiSync",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: [
                "ReaderBookClient.swift",
                "ReaderBookClient+Live.swift",
                "DictionaryLookupClient.swift",
                "DictionaryLookupClient+Live.swift",
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiServices",
            dependencies: [
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: sharedSwiftSettings
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
        .target(
            name: "AmgiCardWeb",
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
