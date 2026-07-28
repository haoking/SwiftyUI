import UIKit
import XCTest

@testable import SwiftyUI

/// SwiftyAlertView 的行为回归。
///
/// 单元测试进程没有 foreground active 的 window scene,`SwiftyGlobal.keyWindow`
/// 恒为 nil —— 这正好构成"无窗口"路径的天然夹具(见 testShowTitleWithoutWindow…)。
/// 另外 SwiftyAlertView 是把自己的 view 直接 addSubview 到 window 上使用的,
/// 并不走真正的 present 流程,UIKit 因此不会自动驱动 viewDidAppear /
/// viewDidDisappear;这也是下面各测试直接手动调用这两个生命周期方法的原因,
/// 与库的实际使用方式一致。UIKit 会为直接调用打印一条 "Calling
/// -viewDidDisappear: directly ... is not supported" 的控制台提示 —— 那是给
/// 正常 present 流程的建议,这里就是要单独驱动这两个方法所注册/撤销的观察者,
/// 提示可以忽略,不影响断言。
@MainActor
final class SwiftyAlertViewTests: XCTestCase {

  /// contentView 的初始 frame:maxY = 600。
  /// 布局本身要靠 viewWillLayoutSubviews 从 key window 算,测试里没有窗口,
  /// 所以直接给一个确定的 frame,让键盘避让的算术结果可预测。
  private static let contentFrame = CGRect(x: 0, y: 400, width: 240, height: 200)
  private static let circleFrame = CGRect(x: 0, y: 340, width: 62, height: 62)
  /// 键盘顶端 y = 500,遮住 contentView 底部 100pt,因此期望位移正好是 100。
  private static let keyboardTopY: CGFloat = 500
  private static let expectedShift: CGFloat = 100

  private func makeAlert() -> SwiftyAlertView {
    let alert = SwiftyAlertView.create()
    alert.contentView.frame = Self.contentFrame
    alert.circleBG.frame = Self.circleFrame
    return alert
  }

  private func postKeyboardWillShow() {
    NotificationCenter.default.post(
      name: UIResponder.keyboardWillShowNotification,
      object: nil,
      userInfo: [
        UIResponder.keyboardFrameEndUserInfoKey: NSValue(
          cgRect: CGRect(x: 0, y: Self.keyboardTopY, width: 390, height: 300))
      ])
  }

  private func postKeyboardWillHide() {
    NotificationCenter.default.post(
      name: UIResponder.keyboardWillHideNotification, object: nil, userInfo: nil)
  }

  // MARK: - B20 回归:键盘避让

  /// B20:两个观察者曾经都注册在 keyboardWillShowNotification 上。按注册顺序,
  /// 第一个把 alert 上移,第二个(函数体是"键盘收起"的还原逻辑)在**同一次**
  /// 通知派发里立刻把 origin 还原并清空,每次键盘弹出的净效果恒为零 ——
  /// 键盘避让整体失效,而 addTextField() 存在的意义正是配合键盘。
  ///
  /// 判别力:把第二个观察者改回 keyboardWillShowNotification,下面第一组断言
  /// (弹出后应当发生位移)必然失败,因为位移会被同一次派发立刻抵消。
  func testKeyboardShowShiftsContentAndHideRestoresIt() {
    let alert = makeAlert()
    alert.viewDidAppear(false)
    defer { alert.viewDidDisappear(false) }

    postKeyboardWillShow()
    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y - Self.expectedShift,
      accuracy: 0.5,
      "键盘弹出后 contentView 必须上移;净位移为零说明两个观察者又注册在同一个通知上了(B20)")
    XCTAssertEqual(
      alert.circleBG.frame.origin.y, Self.circleFrame.origin.y - Self.expectedShift,
      accuracy: 0.5,
      "圆形图标背景必须跟随 contentView 一起上移(B20)")
    XCTAssertTrue(alert.keyboardHasBeenShown)

    postKeyboardWillHide()
    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "键盘收起后 contentView 必须复位")
    XCTAssertEqual(
      alert.circleBG.frame.origin.y, Self.circleFrame.origin.y, accuracy: 0.5,
      "键盘收起后圆形图标背景必须复位")
    XCTAssertFalse(alert.keyboardHasBeenShown)
    XCTAssertNil(alert.tmpContentViewFrameOrigin, "复位后保存的原始 origin 应被清空")
    XCTAssertNil(alert.tmpCircleViewFrameOrigin)
  }

  // MARK: - B21 回归:观察者的撤销与累积

  /// B21:`removeObserver(self, name:)` 对 block 形式注册的观察者是空操作,
  /// 观察者在 viewDidDisappear 之后仍然存活并继续响应键盘通知。
  ///
  /// 判别力:把撤销改回 `removeObserver(self, name:)`,下面的断言必然失败 ——
  /// 已经 dismiss 的 alert 会被键盘通知继续挪动。
  func testKeyboardObserversAreRemovedOnDisappear() {
    let alert = makeAlert()
    alert.viewDidAppear(false)
    alert.viewDidDisappear(false)

    postKeyboardWillShow()

    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "viewDidDisappear 之后观察者必须已被撤销,键盘通知不应再改动 frame(B21)")
    XCTAssertFalse(
      alert.keyboardHasBeenShown,
      "观察者已撤销,keyboardHasBeenShown 不应被置位(B21)")
  }

  /// B21 的"只增不减"那一面:每展示一次就泄漏两个注册项,且每次键盘事件都会
  /// 把它们全部触发一遍。
  ///
  /// 直接数 NotificationCenter 里的注册项没有公开接口,这里用等价断言:
  /// 让若干个**仍然活着**的实例分别走完一轮 appear→disappear,再 post 一次键盘
  /// 通知 —— 只有当前仍在展示的那个实例应当响应。若撤销无效,已 dismiss 的
  /// 每一个实例都会跟着动,数量随轮数线性增长。
  func testDismissedInstancesDoNotAccumulateObservers() {
    var dismissed: [SwiftyAlertView] = []
    for _ in 0..<3 {
      let alert = makeAlert()
      alert.viewDidAppear(false)
      alert.viewDidDisappear(false)
      dismissed.append(alert)
    }

    let showing = makeAlert()
    showing.viewDidAppear(false)
    defer { showing.viewDidDisappear(false) }

    postKeyboardWillShow()

    for (index, alert) in dismissed.enumerated() {
      XCTAssertEqual(
        alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
        "第 \(index) 个实例已 dismiss,它的观察者不应再被触发(B21:注册项逐次累积)")
    }
    XCTAssertEqual(
      showing.contentView.frame.origin.y, Self.contentFrame.origin.y - Self.expectedShift,
      accuracy: 0.5,
      "仍在展示的实例应当正常避让 —— 否则本测试对 B21 没有判别力")
  }

  /// viewDidAppear 未必与 viewDidDisappear 严格配对。连续两次 appear 时若直接
  /// 用新 token 覆盖旧 token,旧观察者就永远失去了被撤销的机会 —— B21 的泄漏
  /// 换了个入口而已。断言:两次 appear 之后再 disappear,观察者必须全部撤净。
  func testRepeatedAppearDoesNotStrandObservers() {
    let alert = makeAlert()
    alert.viewDidAppear(false)
    alert.viewDidAppear(false)
    alert.viewDidDisappear(false)

    postKeyboardWillShow()

    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "重复 appear 遗留的旧观察者必须一并被撤销")
  }

  // MARK: - selfReference 泄漏回归

  /// 无 window 时 showTitle 提前返回,实例必须仍可释放。
  ///
  /// selfReference 是展示期间的自持有,只在 hideView() 的 completion 里清空;
  /// 若它在 keyWindow 守卫**之前**被赋值,提前返回的分支就永远到不了清空点,
  /// 实例永久泄漏。1.x 这条路径是 `keyWindow!` 的无条件崩溃,所以这个泄漏是
  /// 2.0 加固 B1 时引入的新回归。
  func testShowTitleWithoutWindowDoesNotLeakInstance() {
    XCTAssertNil(
      SwiftyGlobal.keyWindow,
      "前提:测试进程没有 foreground active 的 window scene,否则本测试没有判别力")

    weak var weakAlert: SwiftyAlertView?
    autoreleasepool {
      let alert = SwiftyAlertView.create()
      weakAlert = alert
      _ = alert.showTitle("标题", subTitle: "副标题", style: .info)
    }

    // UIKit 可能把实例暂留在 autorelease pool 之外,轮询等待而不是立即断言
    let deadline = Date().addingTimeInterval(3.0)
    while weakAlert != nil && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    XCTAssertNil(
      weakAlert,
      "无 window 时提前返回不应留下 selfReference 自持有,否则实例永久泄漏")
  }

  /// 无 window 时仍返回可用的 responder(签名承诺),且不崩溃。
  func testShowTitleWithoutWindowStillReturnsResponder() {
    let alert = SwiftyAlertView.create()
    let responder = alert.showTitle("标题", subTitle: "副标题", style: .success)
    responder.setTitle("改过的标题")
    XCTAssertEqual(alert.labelTitle.text, "改过的标题")
    XCTAssertFalse(alert.isShowing())
  }

  // MARK: - UIScreen.main 回归

  /// setup() 的初始 frame 必须来自 key window,不能来自 UIScreen.main。
  ///
  /// UIScreen.main 自 iOS 16 起废弃,且在多窗口 / 分屏下返回整块物理屏幕而不是
  /// alert 实际所在窗口的尺寸(与 B17、B1 同一缺陷类)。测试进程没有 key window,
  /// 因此正确实现下初始 frame 应为 .zero;若退回 UIScreen.main.bounds,
  /// 它会是模拟器整屏尺寸。
  func testSetupSizesFromKeyWindowNotUIScreen() {
    XCTAssertNil(SwiftyGlobal.keyWindow, "前提:测试进程没有 foreground active 的 window scene")
    XCTAssertNotEqual(
      UIScreen.main.bounds, .zero,
      "前提:UIScreen.main.bounds 非零,否则本测试无判别力")

    let alert = SwiftyAlertView.create()
    XCTAssertEqual(
      alert.view.frame, .zero,
      "无 key window 时初始 frame 应为 .zero;等于 UIScreen.main.bounds 说明又用回了废弃的 UIScreen.main")
    XCTAssertEqual(alert.baseView.frame, .zero)
  }
}
