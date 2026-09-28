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

  /// SwiftyButton 默认以按钮身份暴露给无障碍,label 取标题;显式设置优先。
  ///
  /// 它继承 UIControl、标题由 SwiftyLabel 自绘,不像 UIButton 那样自带无障碍暴露。
  /// 曾经什么都不设:在无障碍树里只是一个匿名元素,VoiceOver 读不出、UI 测试也点不到,
  /// 示例 App 只能在调用点手工补。
  ///
  /// 判别力:删掉 init 里的两项默认值与 accessibilityLabel 覆写,前三条断言失败。
  func testExposesItselfToAccessibilityAsButton() {
    let button = SwiftyButton("OK", nil, ClosureWrapper { _ in })
    XCTAssertTrue(button.isAccessibilityElement)
    XCTAssertTrue(button.accessibilityTraits.contains(.button))
    XCTAssertEqual(button.accessibilityLabel, "OK")

    button.titleLabel.text = "Go"
    XCTAssertEqual(button.accessibilityLabel, "Go", "label 应跟随当前标题")

    button.accessibilityLabel = "自定义"
    XCTAssertEqual(button.accessibilityLabel, "自定义", "显式设置的 label 优先")
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

  /// 目标-动作接线的回归保护。
  ///
  /// 三个点击测试直接调用 btnTapped 以绕开 sendActions(for:) 在本测试目标中的
  /// 失效问题,代价是不再覆盖 init 里的 addTarget 注册。若该行被删除、
  /// 事件掩码被改、或选择器名写错,那三个测试都不会失败 —— 本测试补上这一层。
  func testTapHandlerIsRegisteredForTouchUpInside() {
    let button = SwiftyButton(nil, nil, ClosureWrapper { _ in })
    XCTAssertEqual(
      button.actions(forTarget: button, forControlEvent: .touchUpInside),
      ["btnTapped:"],
      "init 应把 btnTapped 注册到 .touchUpInside;若此断言失败,说明接线被改动了")
  }

  // 本文件用 `button.btnTapped(button)` 直接调用来模拟点击,而不是 brief 原文的
  // `button.sendActions(for: .touchUpInside)`。原因(实测确认,非猜测):这个
  // SPM 测试 target 没有宿主 App,`UIApplication.shared` 处于不可用状态,
  // `UIControl.sendActions(for:)` 的默认实现依赖它做实际分发,在本环境下
  // 是彻底的 no-op——即便手动挂到 UIWindow 并 makeKeyAndVisible 也一样,
  // 用 `actions(forTarget:forControlEvent:)` 验证过 target/action 确实注册
  // 成功,只是分发这一步没有发生。这与本任务要改的代码无关,是仓库里第一次
  // 写涉及 UIControl 分发的测试时才暴露的环境限制。
  //
  // `btnTapped` 因此从 `@objc private` 放宽为 internal,让 `@testable import`
  // 能直接调用到。注意这与 Task 13 把 mergedAttributedText 改为 internal
  // **不是同一类变更**——那个属性此前是 public,Task 13 是收紧;这里是从
  // private 放宽,之所以可接受,是因为 @objc 方法本就经 ObjC 运行时对外
  // 可达,Swift 访问级别并不构成真正的封装边界。防抖逻辑本就整个搬进了
  // btnTapped 内部,直接调用它测的正是 Step 3 要验证的行为本身。
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

  /// 回归保护:init 中设置的 backgroundImage 必须真的到达 layer.contents。
  ///
  /// Swift 的属性观察器对"在本类自身初始化器中直接赋值自有存储属性"不触发,
  /// 所以仅断言 button.backgroundImage != nil 是不够的 —— 那个值确实被存了,
  /// 只是没有推给 layer。上面的 testInitAppliesTitleAndImage 正是只断言了
  /// 存储属性,因而漏掉了这个回归(Task 19 在 iOSExample 里实跑才发现:按钮
  /// 渲染成空白方块)。
  func testInitPushesBackgroundImageToLayer() {
    let image = TestSupport.makeSolidImage(color: .red)
    let button = SwiftyButton("t", image, ClosureWrapper { _ in })
    XCTAssertNotNil(button.layer.contents, "init 设置的图片必须到达 layer.contents")
  }
}
