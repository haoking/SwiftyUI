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

  /// 窗口不在屏幕原点时(iPad 分屏、台前调度),键盘避让也要算对。
  ///
  /// 键盘的 end frame 是**屏幕**坐标,contentView / circleBG 的 frame 在 baseView 的坐标系里。
  /// 曾经两者直接相减,只在窗口铺满屏幕时才恰好正确。
  ///
  /// 夹具:窗口原点在屏幕 (0, 100);键盘顶端在屏幕 y = 500,换到窗口里是 y = 400,
  /// 遮住 contentView(maxY = 600)底部 200pt。
  ///
  /// 判别力:去掉坐标换算,位移只有 600 − 500 = 100,本测试变红。
  func testKeyboardAvoidanceConvertsFromScreenCoordinates() {
    let window = UIWindow(frame: CGRect(x: 0, y: 100, width: 390, height: 700))
    window.isHidden = false
    let alert = makeShowingAlert()
    defer { alert.hideView() }
    alert.view.frame = window.bounds
    alert.baseView.frame = alert.view.bounds
    window.addSubview(alert.view)

    postKeyboardWillShow()

    XCTAssertEqual(
      alert.contentView.frame.origin.y, Self.contentFrame.origin.y - 200, accuracy: 0.5,
      "键盘 frame 必须先从屏幕坐标换到 baseView 的坐标系再算遮挡")
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

  /// 键盘**还弹着**的时候收起 alert,不能留下过期的键盘簿记。
  ///
  /// tmpContentViewFrameOrigin / tmpCircleViewFrameOrigin / keyboardHasBeenShown
  /// 由显示观察者写入、由**隐藏**观察者清理。而 hideView() 把
  /// removeKeyboardObservers() 提到了消失动画之前,所以这条路径上隐藏观察者
  /// 在键盘真正收起之前就已经被撤销 —— 它的清理永远不会发生。
  ///
  /// testKeyboardAvoidanceFollowsShowHideLifecycle 覆盖不到这里:那条用例在
  /// 调用 hideView() 之前先 post 了 keyboardWillHide,隐藏观察者还活着,
  /// 三个字段是被它清干净的。本用例特意**不**收键盘就直接 hideView()。
  ///
  /// 判别力:把 removeKeyboardObservers() 末尾那三行重置删掉,后三条断言全红。
  func testHidingWhileKeyboardIsUpLeavesNoStaleKeyboardState() {
    let alert = makeShowingAlert()

    postKeyboardWillShow()
    XCTAssertTrue(alert.keyboardHasBeenShown, "前提:键盘已弹起并被记录,否则本测试无判别力")
    XCTAssertNotNil(alert.tmpContentViewFrameOrigin, "前提:原始 origin 已被保存")
    XCTAssertNotNil(alert.tmpCircleViewFrameOrigin)

    // 不 post keyboardWillHide —— 键盘仍然弹着,此时收起 alert。
    alert.hideView()

    XCTAssertFalse(
      alert.keyboardHasBeenShown,
      "撤销观察者时必须一并清掉 keyboardHasBeenShown —— 它的清理者(隐藏观察者)已经被撤销了")
    XCTAssertNil(
      alert.tmpContentViewFrameOrigin,
      "撤销观察者时必须一并清掉 tmpContentViewFrameOrigin,否则撤销走一半、留一半")
    XCTAssertNil(alert.tmpCircleViewFrameOrigin, "撤销观察者时必须一并清掉 tmpCircleViewFrameOrigin")
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

  // MARK: - 收起之后的按钮

  /// hideView() 收尾时会把每个按钮的 action 清空(打破调用方与 alert 之间的引用环);
  /// 此后再点这些按钮不能崩溃。
  ///
  /// 这不是凭空构造的状态:同一个实例可以再次 showTitle(见 addKeyboardObservers()
  /// 的说明),而 showTitle 不会重建按钮,也不会恢复 action —— 重新上屏的正是这些
  /// action 已被清空的按钮。action 曾是隐式解包可选值,`buttonTapped` 里的
  /// `btn.action()` 因此直接 trap。showTitle 的成功分支在单元测试里走不到
  /// (没有 key window),这里直接驱动收起之后的那一次点击。
  ///
  /// 判别力:把 action 改回 `(() -> Void)!`、调用改回 `btn.action()`,测试进程崩溃。
  func testTappingButtonAfterDismissalDoesNotCrash() {
    let alert = SwiftyAlertView.create()
    let button = alert.addButton("OK") {}

    alert.isPresented = true  // 模拟 showTitle 的成功分支(本进程没有 key window)
    alert.hideView()
    // 收起动画在无窗口时下一轮 RunLoop 就结束,completion 里清空 action
    let deadline = Date().addingTimeInterval(3.0)
    while button.action != nil && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    XCTAssertNil(button.action, "前提:hideView() 的收尾已清空 action,否则本测试无判别力")

    alert.buttonTapped(button)
  }

  /// 按钮的视觉高度是 35pt(viewWillLayoutSubviews 里写死),命中区域必须至少 44pt 高,
  /// 达到 44×44pt 的最小点击目标。
  ///
  /// 只扩命中区、不改视觉。竖排时相邻按钮间隔 10pt(步长 kButtonHeight = 45),上下各扩
  /// 4.5pt 不会与邻居重叠 —— 最后一条断言锁住这个上限。
  ///
  /// 判别力:删掉 SwiftyAlertButton 的 point(inside:with:) 覆写,前两条断言失败。
  func testAlertButtonHitAreaMeetsMinimumTouchTarget() {
    let alert = SwiftyAlertView.create()
    let button = alert.addButton("OK") {}
    button.frame = CGRect(x: 12, y: 100, width: 216, height: 35)

    XCTAssertTrue(button.point(inside: CGPoint(x: 108, y: -4.4), with: nil), "上沿之外 4.4pt 应仍可点中")
    XCTAssertTrue(button.point(inside: CGPoint(x: 108, y: 39.4), with: nil), "下沿之外 4.4pt 应仍可点中")
    XCTAssertFalse(
      button.point(inside: CGPoint(x: 108, y: -5), with: nil), "命中区不应扩出 44pt,以免侵入相邻按钮")
  }

  // MARK: - dismissBlock

  /// dismissBlock 每次上屏只回调一次;从未上屏的 alert 不回调。
  ///
  /// hideView() 曾经不看任何状态:无窗口时 showTitle 提前返回、根本没上屏的 alert,
  /// close() 照样回调 dismissBlock;连续 close() 两次则回调两次。把 dismissBlock
  /// 当作"关掉了一次"的调用方会误计数或重复执行收尾。
  ///
  /// 判别力:删掉 hideView() 里的 `guard isPresented`,两条断言分别得到 1 和 2。
  func testDismissBlockFiresOncePerPresentation() {
    let neverShown = SwiftyAlertView.create()
    let neverShownCount = Box(0)
    neverShown.showTitle("标题", subTitle: "副标题", style: .info)  // 无窗口:提前返回,未上屏
      .setDismissBlock { neverShownCount.value += 1 }
    neverShown.hideView()

    let shown = SwiftyAlertView.create()
    shown.isPresented = true  // 模拟 showTitle 的成功分支(本进程没有 key window)
    let shownCount = Box(0)
    shown.dismissBlock = { shownCount.value += 1 }
    shown.hideView()
    shown.hideView()

    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    XCTAssertEqual(neverShownCount.value, 0, "从未上屏的 alert 不应回调 dismissBlock")
    XCTAssertEqual(shownCount.value, 1, "一次上屏只应回调一次 dismissBlock")
  }

  /// 经 responder 改标题 / 副标题之后,alert 必须请求重新布局。
  ///
  /// 标题与副标题的高度都在布局时按当时的文本算(见 layoutContents(in:))。
  /// responder 曾经只改文本、不请求布局,上屏后换成更长的文本会溢出原来的框。
  ///
  /// 判别力:删掉 responder 里的 setNeedsLayout(),两条主断言都失败。
  func testResponderTextChangesRequestRelayout() {
    let alert = SwiftyAlertView.create()
    let responder = SwiftyAlertViewResponder(alertview: alert)
    alert.view.layoutIfNeeded()
    XCTAssertFalse(alert.view.layer.needsLayout(), "前提:布局已经做过一次,否则本测试无判别力")

    responder.setTitle("一个明显更长、需要折行的标题")
    XCTAssertTrue(alert.view.layer.needsLayout(), "改标题后必须请求重新布局")

    alert.view.layoutIfNeeded()
    responder.setSubTitle("一段明显更长、需要折行的副标题")
    XCTAssertTrue(alert.view.layer.needsLayout(), "改副标题后必须请求重新布局")
  }

  /// 重新布局时,标题 label 自己的高度也要按当前文本重算。
  ///
  /// 标题 label 的高度曾经只在 showTitle 里设过一次;布局时虽然按新标题算了高度、
  /// 把副标题往下挪,label 本身却还是旧高度,多出来的行被截断。
  ///
  /// 判别力:删掉 layoutContents(in:) 里对 labelTitle 高度的赋值,两次高度相同。
  func testRelayoutResizesTitleLabelToCurrentText() {
    let alert = SwiftyAlertView.create()
    let responder = SwiftyAlertViewResponder(alertview: alert)
    let size = CGSize(width: 402, height: 874)

    responder.setTitle("短")
    alert.layoutContents(in: size)
    let oneLine = alert.labelTitle.frame.height

    responder.setTitle(String(repeating: "一个需要折成好几行的很长的标题", count: 3))
    alert.layoutContents(in: size)

    XCTAssertGreaterThan(
      alert.labelTitle.frame.height, oneLine * 2, "标题变成多行后,label 的高度必须随之增长")
  }

  // MARK: - 布局(经 layoutContents(in:) 直接喂尺寸)

  /// 横排的按钮必须都落在 contentView 之内,左右边距与相邻间距一致。
  ///
  /// 横排布局曾在每个按钮之后加上 buttonsSpace —— 那是**总**间距 10×(n−1),
  /// 不是单个间距 10。两个按钮时两者相等所以看不出来;三个按钮起间距翻倍,
  /// 最后一个按钮越出 contentView,被 masksToBounds 裁掉。
  ///
  /// 判别力:改回 `buttonX += buttonsSpace`,三个按钮时最后一个的右缘在 248 > 240。
  func testHorizontalButtonsStayInsideContentView() {
    let alert = SwiftyAlertView.create(SwiftyAlertView.SwiftyAppearance(buttonsLayout: .horizontal))
    for title in ["A", "B", "C"] { alert.addButton(title) {} }

    alert.layoutContents(in: CGSize(width: 402, height: 874))

    let content = alert.contentView.bounds
    for (index, button) in alert.buttons.enumerated() {
      XCTAssertTrue(
        content.contains(button.frame),
        "第 \(index) 个按钮越出了 contentView(\(button.frame),容器 \(content))")
    }
    let last = try! XCTUnwrap(alert.buttons.last)
    XCTAssertEqual(content.maxX - last.frame.maxX, 12, accuracy: 0.5, "右边距应与左边距同为 12pt")
    for (left, right) in zip(alert.buttons, alert.buttons.dropFirst()) {
      XCTAssertEqual(right.frame.minX - left.frame.maxX, 10, accuracy: 0.5, "相邻按钮间距应为 10pt")
    }
  }

  /// 文本框的视觉高度是 30pt,命中区域同样必须至少 44pt 高。
  ///
  /// 与按钮同一个做法:只扩命中区,不改视觉。文本框之间的步长是 kTextFieldHeight(45),
  /// 间隔 15pt,上下各扩 7pt 不会与相邻文本框重叠 —— 最后一条断言锁住上限。
  ///
  /// 判别力:让 addTextField() 返回普通 UITextField,前两条断言失败。
  func testAlertTextFieldHitAreaMeetsMinimumTouchTarget() {
    let alert = SwiftyAlertView.create()
    let field = alert.addTextField()
    field.frame = CGRect(x: 12, y: 100, width: 216, height: 30)

    XCTAssertTrue(field.point(inside: CGPoint(x: 108, y: -6.9), with: nil), "上沿之外 6.9pt 应仍可点中")
    XCTAssertTrue(field.point(inside: CGPoint(x: 108, y: 36.9), with: nil), "下沿之外 6.9pt 应仍可点中")
    XCTAssertFalse(
      field.point(inside: CGPoint(x: 108, y: -7.5), with: nil), "命中区不应扩出 44pt,以免侵入相邻文本框")
  }

  /// alert 是模态遮罩,VoiceOver 焦点不能跑到它后面的内容上。
  ///
  /// 判别力:删掉 setup() 里的 accessibilityViewIsModal = true,本断言失败。
  func testAlertRootViewIsAccessibilityModal() {
    XCTAssertTrue(SwiftyAlertView.create().view.accessibilityViewIsModal)
  }

  /// 五种样式的默认配色,按钮文字与按钮底色的对比度都必须达到 WCAG AA(正文 4.5:1)。
  ///
  /// 按钮字体是 14pt 粗体,不算 WCAG 的"大字",适用 4.5:1。圆圈里的图标与按钮同色、
  /// 同为白色(warning 为深灰),因此也一并满足非文本 3:1。文字色取各 showXxx 的默认参数
  /// (warning 为黑,其余为白)。success 曾是 #22B573,白字只有 2.65:1。
  ///
  /// 判别力:把 success 改回 0x22B573,本测试报出 2.65。
  func testDefaultStyleColorsMeetContrastMinimum() {
    let defaultTextColors: [(SwiftyAlertViewStyle, UInt)] = [
      (.success, 0xFFFFFF), (.error, 0xFFFFFF), (.warning, 0x000000), (.info, 0xFFFFFF),
      (.edit, 0xFFFFFF),
    ]
    for (style, text) in defaultTextColors {
      let ratio = Self.contrastRatio(style.defaultColorInt, text)
      XCTAssertGreaterThanOrEqual(
        ratio, 4.5, "\(style) 的按钮文字对比度只有 \(String(format: "%.2f", ratio)):1")
    }
  }

  /// WCAG 2.x 的对比度:(较亮的相对亮度 + 0.05) / (较暗的 + 0.05)。
  private static func contrastRatio(_ a: UInt, _ b: UInt) -> Double {
    func luminance(_ hex: UInt) -> Double {
      func channel(_ value: UInt) -> Double {
        let c = Double(value & 0xFF) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }
    let (la, lb) = (luminance(a), luminance(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
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
