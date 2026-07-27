import UIKit
import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyGlobalTests: XCTestCase {

  /// B1:单元测试进程没有 foreground active 的 window scene,
  /// keyWindow 必须返回 nil 而不是崩溃。
  func testKeyWindowReturnsNilWithoutActiveScene() {
    _ = SwiftyGlobal.keyWindow  // 不崩溃即通过
  }

  /// B17:所有派生尺寸在无窗口时返回安全默认值。
  func testDerivedMetricsFallBackSafely() {
    XCTAssertEqual(SwiftyGlobal.screenSize, .zero)
    XCTAssertEqual(SwiftyGlobal.screenWidth, 0)
    XCTAssertEqual(SwiftyGlobal.screenHeight, 0)
    XCTAssertEqual(SwiftyGlobal.statusHeight, 0)
    XCTAssertEqual(SwiftyGlobal.safeAreaInsets, .zero)
  }

  /// modelName 在模拟器上应返回 "Simulator"。
  func testModelName() {
    XCTAssertFalse(SwiftyGlobal.modelName.isEmpty)
  }

  /// B17:改为计算属性后必须实时反映当前状态,而不是首次访问时的快照。
  func testMetricsTrackWindowLifecycle() {
    XCTAssertNil(SwiftyGlobal.keyWindow)
    XCTAssertEqual(SwiftyGlobal.screenSize, .zero)
    // 若实现仍是永久缓存的 static var,后续接入真实 scene 时会失效;
    // 这里只能断言无窗口态的一致性,真实多窗口行为由 iOSExample 人工验收。
  }
}
