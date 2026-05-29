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
    name: "AmgiReader",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AmgiReader", targets: ["AmgiReader"]),
        .library(name: "AmgiReaderDictionary", targets: ["AmgiReaderDictionary"]),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(path: "../Libraries/EPUBKit"),
        .package(url: "https://github.com/Manhhao/hoshidicts.git", revision: "e70589d33b6b346663278383b422e41f1ed05f3c"),
    ],
    targets: [
        .target(
            name: "AmgiReader",
            dependencies: [
                .product(name: "AnkiKit", package: "Amgi"),
                .product(name: "AnkiBackend", package: "Amgi"),
                .product(name: "AnkiClients", package: "Amgi"),
                .product(name: "AnkiServices", package: "Amgi"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "EPUBKit", package: "EPUBKit"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AmgiReaderDictionary",
            dependencies: [
                "AmgiReader",
                .product(name: "AnkiBackend", package: "Amgi"),
                .product(name: "CHoshiDicts", package: "hoshidicts"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            path: "Sources/AmgiReaderDictionary",
            swiftSettings: sharedSwiftSettings + [
                .interoperabilityMode(.Cxx),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
