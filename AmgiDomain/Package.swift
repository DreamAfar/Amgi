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
    name: "AmgiDomain",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AmgiDomain", targets: ["AmgiDomain"]),
    ],
    targets: [
        .target(
            name: "AmgiDomain",
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
