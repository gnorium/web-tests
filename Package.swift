// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "web-tests",
  // Drives a browser installed on this Mac (Chrome over the DevTools Protocol,
  // Safari over safaridriver), so macOS only for now.
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "WebTests", targets: ["WebTests"]),
    .library(name: "WebTestsTesting", targets: ["WebTestsTesting"]),
  ],
  targets: [
    .target(
      name: "WebTests",
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("StrictConcurrency"),
      ]
    ),
    .target(
      name: "WebTestsTesting",
      dependencies: ["WebTests"],
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("StrictConcurrency"),
      ]
    ),
    .testTarget(
      name: "WebTestsTests",
      dependencies: ["WebTests", "WebTestsTesting"]
    ),
    .testTarget(
      name: "GnoriumWebTests",
      dependencies: ["WebTests", "WebTestsTesting"]
    ),
  ]
)
