// swift-tools-version: 6.2
import PackageDescription

// Local modules have their own Project.swift; only remote dependencies live here.
let package = Package(
    name: "AmgiDependencies",
    dependencies: [
        .package(url: "https://github.com/tadija/AEXML", from: "4.7.0"),
        .package(url: "https://github.com/ZipArchive/ZipArchive", from: "2.6.0"),
        .package(url: "https://github.com/Manhhao/hoshidicts.git", revision: "a28d82eb0f169b8ceff79e8c99ffe0b96709ab27"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ]
)
