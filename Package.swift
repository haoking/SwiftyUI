// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftyUI",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(
      name: "SwiftyUI",
      targets: ["SwiftyUI"])
  ],
  targets: [
    .target(
      name: "SwiftyUI",
      path: "Sources"),
    .testTarget(
      name: "SwiftyUITests",
      dependencies: ["SwiftyUI"],
      path: "Tests/SwiftyUITests"),
  ]
)
