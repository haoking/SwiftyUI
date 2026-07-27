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
      path: "Sources",
      // Task 17 会移除这一行,切换到 tools 6.0 默认的 Swift 6 语言模式
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(
      name: "SwiftyUITests",
      dependencies: ["SwiftyUI"],
      path: "Tests/SwiftyUITests",
      swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
