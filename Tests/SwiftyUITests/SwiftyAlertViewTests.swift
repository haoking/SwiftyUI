import UIKit
import XCTest

@testable import SwiftyUI

/// SwiftyAlertView 的行为回归。
///
/// **这个测试进程里没有任何 window scene**(`UIApplication.shared.connectedScenes`
/// 为空,已实测确认),因此 `SwiftyGlobal.keyWindow` 恒为 nil。两个后果:
///
/// 1. "无窗口"路径有了天然夹具(见 testShowTitleWithoutWindow…)。
/// 2. `showTitle` 的**成功**分支在这里根本走不到 —— 它第一步就要 key window。
///    所以下面用 `addKeyboardObservers()`(internal,专为此开放)直接驱动
///    "开始展示"这一步,再用真正的 `hideView()` 驱动"结束展示"。
///    "showTitle 的成功分支确实调用了 addKeyboardObservers()"这一条连接,
///    单元测试环境无法覆盖,只能靠代码审查与 iOSExample 人工验收。
///
/// 键盘观察者的注册/撤销**不**挂在 viewDidAppear / viewDidDisappear 上,
/// 而是由 showTitle / hideView() 驱动。
///
/// 理由**不是**"那两个回调不触发"。实测(iOS 26.5 模拟器)它们会触发,
/// 尽管 SwiftyAlertView 只是把自己的 view 裸 addSubview 到 window 上 ——
/// 不 present、不做容器包含、也不是 rootViewController,按经典 UIKit 规则
/// 这种位置的控制器不该收到外观回调,而实际行为与规则不符。
/// 真正的理由是**不去依赖这个没有契约保证的行为**,外加与本类型自带的展示
/// 生命周期(selfReference 自持有/清理)确定性配对。
/// 详见 Sources/SwiftyAlertView.swift 中 addKeyboardObservers() 的说明。
@MainActor
final class SwiftyAlertViewTests: XCTestCase {

  /// contentView 的初始 frame:maxY = 600。
  /// 布局本来要靠 viewWillLayoutSubviews 从 key window 算,这里没有窗口,
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

  /// 模拟 showTitle 成功展示的那一步(见类型注释:成功分支需要 key window,
  /// 本进程没有)。
  private func makeShowingAlert() -> SwiftyAlertView {
    let alert = makeAlert()
    alert.addKeyboardObservers()
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

  // MARK: - 键盘避让的完整生命周期(B20 + B21 + 注册点)

  /// 一条龙:展示 → 键盘弹出应上移 → 键盘收起应复位 → hideView() → 再弹键盘
  /// 不应再有任何反应。
  ///
  /// 这一个测试同时守住三件事,任何一件退回去都会变红:
  /// - **B20**:两个观察者若都注册在 keyboardWillShowNotification 上,第二个会在
  ///   同一次派发里把第一个的位移抵消,净效果恒为零 → 第一组断言失败。
  /// - **B21**:撤销若退回 `removeObserver(self, name:)`(对 block 形式注册是
  ///   空操作)→ 最后一组断言失败。
  /// - **注册点**:撤销必须由 hideView() 驱动。搬回 viewDidDisappear 之后,
  ///   hideView() 自己就不再撤销任何东西 → 最后一组断言同样失败。
  func testKeyboardAvoidanceFollowsShowHideLifecycle() {
    let alert = makeShowingAlert()

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

    // 收起 alert:观察者必须随之撤销
    alert.hideView()
    postKeyboardWillShow()
    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "hideView() 之后观察者必须已被撤销,键盘通知不应再改动 frame")
    XCTAssertFalse(
      alert.keyboardHasBeenShown,
      "hideView() 之后观察者已撤销,keyboardHasBeenShown 不应被置位")
  }

  /// 注册点不再是外观回调。
  ///
  /// 注意这条锁定的**不是**"外观回调不触发"——实测它们会触发(见类型注释)。
  /// 锁定的是"本库不去依赖 UIKit 在这个位置没有契约保证的行为":一个只被裸
  /// addSubview 到 window 上的控制器,按规则不该收到外观回调,实际却收到了;
  /// 哪一边将来会变谁也不知道,所以注册/撤销改由本类型自己的展示生命周期
  /// (showTitle / hideView())驱动。本测试断言:单独驱动 viewDidAppear
  /// 不应让这个 alert 开始响应键盘。
  func testAppearanceCallbacksDoNotDriveKeyboardObservation() {
    let alert = makeAlert()
    alert.viewDidAppear(false)

    postKeyboardWillShow()

    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "viewDidAppear 不应注册键盘观察者 —— 键盘观察必须只由 showTitle / hideView() 驱动,"
        + "不依赖 UIKit 对这种上屏方式的外观回调行为")
    XCTAssertFalse(alert.keyboardHasBeenShown)
  }

  /// 无 window 时 showTitle 提前返回,这条路径上不应注册任何观察者
  /// (注册排在 keyWindow 守卫之后)—— 注册与撤销必须在每条出口上成对。
  func testShowTitleWithoutWindowRegistersNoObservers() {
    XCTAssertNil(SwiftyGlobal.keyWindow, "前提:测试进程没有 foreground active 的 window scene")

    let alert = makeAlert()
    _ = alert.showTitle("标题", subTitle: "副标题", style: .info)

    postKeyboardWillShow()

    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "未成功展示的 alert 不应有键盘观察者存活")
  }

  // MARK: - B21:观察者不得逐次累积

  /// B21 的"只增不减"那一面:每展示一次就泄漏两个注册项,且每次键盘事件都会
  /// 把它们全部触发一遍。
  ///
  /// 直接数 NotificationCenter 里的注册项没有公开接口,这里用等价断言:
  /// 让若干个**仍然活着**的实例分别走完一轮展示→收起,再 post 一次键盘通知 ——
  /// 只有当前仍在展示的那个实例应当响应。若撤销无效,已收起的每一个实例都会
  /// 跟着动,数量随轮数线性增长。
  func testDismissedInstancesDoNotAccumulateObservers() {
    var dismissed: [SwiftyAlertView] = []
    for _ in 0..<3 {
      let alert = makeShowingAlert()
      alert.hideView()
      dismissed.append(alert)
    }

    let showing = makeShowingAlert()
    defer { showing.hideView() }

    postKeyboardWillShow()

    for (index, alert) in dismissed.enumerated() {
      XCTAssertEqual(
        alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
        "第 \(index) 个实例已收起,它的观察者不应再被触发(B21:注册项逐次累积)")
    }
    XCTAssertEqual(
      showing.contentView.frame.origin.y, Self.contentFrame.origin.y - Self.expectedShift,
      accuracy: 0.5,
      "仍在展示的实例应当正常避让 —— 否则本测试对 B21 没有判别力")
  }

  /// 同一个实例被重复展示时,不能用新 token 覆盖旧 token —— 那会让旧观察者
  /// 永远失去被撤销的机会,是 B21 的泄漏换了个入口。
  /// 断言:重复注册之后一次 hideView() 必须把两轮的观察者都撤净。
  func testRepeatedRegistrationDoesNotStrandObservers() {
    let alert = makeAlert()
    alert.addKeyboardObservers()
    alert.addKeyboardObservers()
    alert.hideView()

    postKeyboardWillShow()

    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y, accuracy: 0.5,
      "重复注册遗留的旧观察者必须一并被撤销")
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
