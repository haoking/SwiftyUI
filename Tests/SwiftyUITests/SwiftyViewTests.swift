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

    // init 在 super.init 之后设置 backgroundColor = .clear,属于 Swift 初始化的
    // 第二阶段,didSet 观察器必然触发。.clear 的 alpha 为 0,故 isOpaque 应为 false。
    // 这条断言保护的是"观察器确实跨 init 边界生效"这一前提。
    XCTAssertFalse(view.isOpaque, "init 中的 backgroundColor 赋值应触发观察器并重算 isOpaque")
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

  /// B15:未显式开启全局优化时,库不应改写普通 UIView 的 isOpaque。
  ///
  /// 判别力的关键是用**半透明**背景色:UIView 的 isOpaque 系统默认为 true
  /// 且不随 backgroundColor 变化。若全局 swizzle 被意外装上,它会被重算为 false。
  /// 用不透明色(如 .red)则无判别力 —— 那种情况下重算结果同样是 true。
  ///
  /// - Important: 本测试今天能过,前提是**整个测试进程里没有任何人调用过**
  ///   `SwiftyUI.enableGlobalOpaqueOptimization()`。那个方法对 UIView 做的是
  ///   进程级、**不可撤销**的方法交换(见它自己的文档),没有任何 tearDown 能
  ///   把它还原。所以:不要在任何测试里调用它 —— 一旦调用,不只是本测试,
  ///   同进程内此后所有依赖"UIView 默认行为"的测试都会跟着失真,而且改动本身
  ///   在 diff 里看起来完全无害。要覆盖开启后的行为,只能另起一个测试进程。
  func testPlainUIViewIsUnaffectedByDefault() {
    let plain = UIView()
    plain.backgroundColor = UIColor.red.withAlphaComponent(0.5)
    XCTAssertTrue(
      plain.isOpaque,
      "未开启全局优化时,普通 UIView 的 isOpaque 应保持系统默认值 true,不因半透明背景被重算")

    // addTo 也不应有任何副作用(1.x 在此惰性装载全局 swizzle)
    let container = UIView()
    plain.addTo(container)
    XCTAssertTrue(container.subviews.contains(plain))
    XCTAssertTrue(plain.isOpaque, "addTo 不应触发任何 isOpaque 重算")
  }

  func testAddToReturnsSelfForChaining() {
    let container = UIView()
    let view = SwiftyView()
    XCTAssertTrue(view.addTo(container) === view)
  }
}
