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
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(path: "../Libraries/EPUBKit"),
    ],
    targets: [
        .target(
            name: "AmgiReader",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "EPUBKit", package: "EPUBKit"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
