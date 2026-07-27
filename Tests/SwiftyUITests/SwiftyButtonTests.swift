import UIKit
import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyButtonTests: XCTestCase {

  func testInitAppliesTitleAndImage() {
    let image = TestSupport.makeSolidImage(color: .red)
    let button = SwiftyButton("tap", image, ClosureWrapper { _ in })
    XCTAssertEqual(button.titleLabel.text, "tap")
    XCTAssertNotNil(button.backgroundImage)
  }

  /// B3:backgroundImage 往返不应丢失 scale
  func testBackgroundImageRoundTripPreservesScale() {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    let scaled = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format)
      .image { ctx in
        UIColor.red.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
      }

    let button = SwiftyButton(nil, scaled, ClosureWrapper { _ in })
    XCTAssertEqual(
      button.backgroundImage?.scale, 3.0,
      "backgroundImage 往返后 scale 应保持不变(B3)")
  }

  // 本文件用 `button.btnTapped(button)` 直接调用来模拟点击,而不是 brief 原文的
  // `button.sendActions(for: .touchUpInside)`。原因(实测确认,非猜测):这个
  // SPM 测试 target 没有宿主 App,`UIApplication.shared` 处于不可用状态,
  // `UIControl.sendActions(for:)` 的默认实现依赖它做实际分发,在本环境下
  // 是彻底的 no-op——即便手动挂到 UIWindow 并 makeKeyAndVisible 也一样,
  // 用 `actions(forTarget:forControlEvent:)` 验证过 target/action 确实注册
  // 成功,只是分发这一步没有发生。这与本任务要改的代码无关,是仓库里第一次
  // 写涉及 UIControl 分发的测试时才暴露的环境限制。`btnTapped` 因此改为
  // internal(而非 1.x 的 private),同样是为了让 `@testable import` 能直接
  // 调用到——与 Task 13 把 mergedAttributedText 从 private 改 internal 的
  // 理由一致。防抖逻辑本就整个搬进了 btnTapped 内部,直接调用它测的正是
  // Step 3 要验证的行为本身。
  func testTapInvokesHandler() {
    var tapCount = 0
    let button = SwiftyButton(nil, nil, ClosureWrapper { _ in tapCount += 1 })
    button.btnTapped(button)
    XCTAssertEqual(tapCount, 1)
  }

  func testRapidTapsAreDebounced() {
    var tapCount = 0
    let button = SwiftyButton(nil, nil, ClosureWrapper { _ in tapCount += 1 })
    button.btnTapped(button)
    button.btnTapped(button)
    button.btnTapped(button)
    XCTAssertEqual(tapCount, 1, "忽略窗口内的重复点击应被丢弃")
  }

  func testDebounceCanBeDisabled() {
    var tapCount = 0
    let button = SwiftyButton(nil, nil, ClosureWrapper { _ in tapCount += 1 })
    button.ignoreEventInterval = 0
    button.btnTapped(button)
    button.btnTapped(button)
    XCTAssertEqual(tapCount, 2)
  }
}
