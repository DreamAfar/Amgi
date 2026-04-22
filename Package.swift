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
        .library(name: "AnkiReader", targets: ["AnkiReader"]),
        .library(name: "AnkiSync", targets: ["AnkiSync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/Manhhao/hoshidicts.git", revision: "e70589d33b6b346663278383b422e41f1ed05f3c"),
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
            name: "AnkiReader",
            dependencies: [
                "AnkiClients",
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                .product(name: "CHoshiDicts", package: "hoshidicts"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            path: "Sources",
            sources: [
                "AnkiKit/ReaderTypes.swift",
                "AnkiKit/DictionaryTypes.swift",
                "AnkiKit/AppDictionaryTypes.swift",
                "AnkiClients/ReaderBookClient.swift",
                "AnkiClients/ReaderBookClient+Live.swift",
                "AnkiClients/DictionaryLookupClient.swift",
                "AnkiClients/DictionaryLookupClient+Live.swift",
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
