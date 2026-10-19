// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Xcode 27 新建 Swift target 默认开启前三个(Approachable Concurrency 与 MemberImportVisibility),
// 后两个让公开接口依赖哪些模块写在明处。五个都是 Swift 7 语言模式的默认行为。
// SwiftyUI.podspec 的 pod_target_xcconfig 与 SwiftyUI.xcodeproj 的框架 target 开同一组,
// 否则同一份源码在不同集成方式下行为不同(NonisolatedNonsendingByDefault 会改变非隔离
// async 函数在哪个执行器上运行)。
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
  name: "SwiftyUI",
  platforms: [
    .iOS(.v18)
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
      swiftSettings: swiftSettings),
    .testTarget(
      name: "SwiftyUITests",
      dependencies: ["SwiftyUI"],
      path: "Tests/SwiftyUITests",
      swiftSettings: swiftSettings),
  ],
  swiftLanguageModes: [.v6]
)
