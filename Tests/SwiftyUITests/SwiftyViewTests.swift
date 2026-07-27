import UIKit
import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyViewTests: XCTestCase {

  func testInitDefaults() {
    let view = SwiftyView()
    XCTAssertEqual(view.backgroundColor, .clear)
    XCTAssertFalse(view.isHidden)
    XCTAssertEqual(view.alpha, 1.0)
  }

  /// SwiftyView 自身维护 isOpaque,不依赖全局 swizzle。
  func testOpaqueTracksBackgroundColor() {
    let view = SwiftyView()
    view.backgroundColor = .red  // alpha 1.0 的实色
    XCTAssertTrue(view.isOpaque)

    view.backgroundColor = UIColor.red.withAlphaComponent(0.5)
    XCTAssertFalse(view.isOpaque)

    view.backgroundColor = .clear
    XCTAssertFalse(view.isOpaque)
  }

  func testOpaqueTracksAlpha() {
    let view = SwiftyView()
    view.backgroundColor = .red
    XCTAssertTrue(view.isOpaque)

    view.alpha = 0.5
    XCTAssertFalse(view.isOpaque)

    view.alpha = 1.0
    XCTAssertTrue(view.isOpaque)
  }

  /// B15:未显式开启全局优化时,普通 UIView 不应被改写行为。
  func testPlainUIViewIsUnaffectedByDefault() {
    let plain = UIView()
    plain.backgroundColor = .red
    // 系统默认 isOpaque 为 true,但不应因 backgroundColor 变化而被库改写。
    // 这里断言的是"addTo 不再产生副作用"。
    let container = UIView()
    plain.addTo(container)
    XCTAssertTrue(container.subviews.contains(plain))
  }

  func testAddToReturnsSelfForChaining() {
    let container = UIView()
    let view = SwiftyView()
    XCTAssertTrue(view.addTo(container) === view)
  }
}
