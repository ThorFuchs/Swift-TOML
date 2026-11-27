// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "Swift-TOML",
    // Floors match Swift Content Collections, the first consumer.
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "TOML", targets: ["TOML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ThorFuchs/Swift-JSON.git", "1.9.0"..<"1.11.0"),
    ],
    targets: [
        .target(
            name: "TOML",
            dependencies: [.product(name: "JSON", package: "Swift-JSON")]
        ),
        .testTarget(
            name: "TOMLTests",
            dependencies: ["TOML", .product(name: "JSON", package: "Swift-JSON")],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
