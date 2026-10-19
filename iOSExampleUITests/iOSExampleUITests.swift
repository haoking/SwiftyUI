//
//  iOSExampleUITests.swift
//  iOSExampleUITests
//
//  Created by Haochen Wang on 10/6/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit
import XCTest

/// iOSExample 的验收用例。
///
/// 这里覆盖的是**单元测试进程里做不到**的那几条:
///
/// - 单元测试 target 没有宿主 App,`UIApplication.shared.connectedScenes` 为空,
///   `SwiftyGlobal.keyWindow` 恒为 nil。凡是"要有窗口才发生"的行为
///   (toast 真的挂上去、alert 真的展示、`showTitle` 的成功分支)在那里全部不可达。
/// - 单元测试也没有触摸与旋转。`UIControl.sendActions(for:)` 在无宿主环境下是
///   no-op(见 SwiftyButton.btnTapped 的注释),防抖只能靠直接调用方法来间接验证;
///   而"三次**真实**快速点击只触发一次"必须有真实触摸事件。
///
/// 断言一律针对**可观察的界面状态**(元素存在性、frame、无障碍文本、屏幕像素),
/// 不针对控制台输出 —— 控制台输出只有连着 Xcode 才看得见,且无法在进程内断言。
/// 示例 App 里那几个原本只 `print` 的回调,现在同时把同一条文本写进屏幕上的
/// EventLog(`print` 一行没删),UI 测试断言的就是这份屏幕状态。
@MainActor
final class iOSExampleUITests: XCTestCase {

  /// 用例第一次碰到它时才启动 App。XCTest 为每个用例新建一个实例,所以仍是每个用例
  /// 启动一次,与原先在 setUp() 里启动等价。
  ///
  /// 不在 setUp() 里启动:Xcode 27 的 XCUIAutomation 把 XCUIApplication、XCUIDevice
  /// 等类型标成了 @MainActor,而 setUp()/tearDown() 继承自 XCTestCase、是非隔离的,
  /// 在里面创建和启动 App 会得到一串主 actor 隔离告警。Xcode 27 的模板同样是在
  /// @MainActor 的用例方法里启动 App。
  private lazy var app: XCUIApplication = {
    let app = XCUIApplication()
    app.launch()
    return app
  }()

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    // 朝向是**进程外**的模拟器状态,不还原会漏给同一次运行里后面的用例。
    // 用 teardown block 而不是在各用例末尾还原:用例中途失败时(continueAfterFailure
    // = false 会直接中止后续代码)也要还原。这个重载的闭包是 @MainActor 的,
    // 可以直接设置 XCUIDevice。
    addTeardownBlock { @MainActor in
      XCUIDevice.shared.orientation = .portrait
    }
  }

  // MARK: - 元素

  private var mainButton: XCUIElement { app.buttons["MainButton"] }
  private var alert: XCUIElement { app.otherElements["SwiftyAlert"] }
  private var toast: XCUIElement { app.staticTexts["SwiftyToast"] }
  private var window: XCUIElement { app.windows.element(boundBy: 0) }
  private var alertCount: Int { app.otherElements.matching(identifier: "SwiftyAlert").count }
  private var eventLog: String { app.staticTexts["EventLog"].label }

  // MARK: - 工具

  /// 轮询等待条件成立。XCUITest 的每次查询本身就要几十毫秒,不需要额外 sleep。
  @discardableResult
  private func waitUntil(
    _ timeout: TimeInterval = 10, _ description: String, _ condition: () -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
    }
    XCTFail("等待超时(\(timeout)s):\(description)")
    return false
  }

  private func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return haystack.components(separatedBy: needle).count - 1
  }

  /// 关掉当前 alert(如果有),并等 toast 队列排空,再点一次主按钮拿一个全新的 toast。
  ///
  /// 必须排空:SwiftyToastCenter 是串行队列,前一个没播完,后一个只会排队不显示。
  private func showFreshToast() {
    if alert.exists {
      app.buttons["First Button"].firstMatch.tap()
      waitUntil(10, "alert 关闭") { !self.alert.exists }
    }
    waitUntil(15, "toast 队列排空") { !self.toast.exists }
    mainButton.tap()
    XCTAssertTrue(toast.waitForExistence(timeout: 10), "点击主按钮后没有出现 toast")
  }

  /// 断言 toast 贴着**当前**窗口的底边居中。
  ///
  /// 这才是"跟着朝向走"的可观察含义:横屏窗口是 874×402,竖屏是 402×874,
  /// 同一个 toast 在两种朝向下都必须落在各自窗口的底部中央。
  private func assertToastAnchoredToBottomCenter(_ context: String) {
    let windowFrame = window.frame
    let toastFrame = toast.frame
    XCTAssertEqual(
      toastFrame.midX, windowFrame.midX, accuracy: 1.0,
      "\(context):toast 没有水平居中(toast=\(toastFrame) window=\(windowFrame))")
    let bottomGap = windowFrame.maxY - toastFrame.maxY
    XCTAssertTrue(
      (15.0...45.0).contains(bottomGap),
      "\(context):toast 离窗口底边 \(bottomGap)pt,不在预期的 15~45pt 内"
        + "(toast=\(toastFrame) window=\(windowFrame))")
    XCTAssertTrue(
      windowFrame.contains(toastFrame),
      "\(context):toast 不在窗口内,用户看不到(toast=\(toastFrame) window=\(windowFrame))")
  }

  /// 取整屏截图上某一点的颜色。用来判定 alert 的**样式**(success / error / …)——
  /// 配色是 SwiftyAlertViewStyle 唯一对外可见的差别,无障碍树里读不到。
  private func screenColor(at point: CGPoint) -> (r: Int, g: Int, b: Int)? {
    let image = XCUIScreen.main.screenshot().image
    guard let cgImage = image.cgImage, image.size.width > 0 else { return nil }
    let scale = CGFloat(cgImage.width) / image.size.width
    let px = Int((point.x * scale).rounded())
    let py = Int((point.y * scale).rounded())
    guard px >= 0, py >= 0, px < cgImage.width, py < cgImage.height,
      let pixel = cgImage.cropping(to: CGRect(x: px, y: py, width: 1, height: 1))
    else { return nil }

    var bytes = [UInt8](repeating: 0, count: 4)
    guard
      let context = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
  }

  /// SwiftyAlertViewStyle.defaultColorInt 的五个取值(Sources/SwiftyAlertStyle.swift)。
  /// 这里不 import SwiftyUI:UI 测试 bundle 不链接被测框架,照抄常量并在此注明出处。
  private static let styleColors: [(name: String, rgb: (r: Int, g: Int, b: Int))] = [
    ("success", (0x19, 0x87, 0x54)),
    ("error", (0xC1, 0x27, 0x2D)),
    ("warning", (0xFF, 0xD1, 0x10)),
    ("info", (0x28, 0x66, 0xBF)),
    ("edit", (0xA4, 0x29, 0xFF)),
  ]

  private func nearestStyleName(to color: (r: Int, g: Int, b: Int)) -> String {
    Self.styleColors.min {
      let da =
        pow(Double($0.rgb.r - color.r), 2) + pow(Double($0.rgb.g - color.g), 2)
        + pow(Double($0.rgb.b - color.b), 2)
      let db =
        pow(Double($1.rgb.r - color.r), 2) + pow(Double($1.rgb.g - color.g), 2)
        + pow(Double($1.rgb.b - color.b), 2)
      return da < db
    }!.name
  }

  /// 等软件键盘真的**出现在屏幕内**。
  ///
  /// 不能只看 `app.keyboards.count > 0`:模拟器接着宿主机硬件键盘时,键盘视图照样
  /// 存在,只是被停靠到屏幕外(实测 frame 为 (0, 952, 402, 233),而屏幕高 874),
  /// 此时 keyboardWillShow 带的 frame 也在屏幕外,alert 按设计就不该移动。
  /// 那种环境下本用例无法成立,必须显式报错,而不是"没动=通过"。
  private func waitForKeyboardOnScreen(timeout: TimeInterval = 10) -> Bool {
    let screenHeight = window.frame.height
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if app.keyboards.count > 0 {
        let frame = app.keyboards.element(boundBy: 0).frame
        if frame.height > 0 && frame.minY < screenHeight { return true }
      }
    }
    return false
  }

  // MARK: - 验收行:点击按钮 → 出现 Toast 与 success 样式的 Alert

  func testTapShowsToastAndSuccessStyleAlert() {
    XCTAssertTrue(mainButton.waitForExistence(timeout: 10))
    mainButton.tap()

    XCTAssertTrue(toast.waitForExistence(timeout: 10), "没有出现 toast")
    XCTAssertEqual(toast.label, "btnTappedSelector", "toast 文本不对")

    XCTAssertTrue(alert.waitForExistence(timeout: 10), "没有出现 alert")
    XCTAssertTrue(app.staticTexts["Congratulations"].exists, "alert 标题不对")
    XCTAssertTrue(
      app.staticTexts["You've just displayed this awesome Pop Up View"].exists, "alert 副标题不对")
    XCTAssertTrue(app.buttons["First Button"].exists)
    XCTAssertTrue(app.buttons["Second Button"].exists)
    XCTAssertTrue(app.textFields.firstMatch.exists, "addTextField() 的输入框没出现")

    // success 样式:按钮底色应当是 SwiftyAlertViewStyle.success 的 0x198754。
    // 取按钮左端(标题文字居中,左端是纯色填充),再看它最接近五种样式里的哪一种。
    let button = app.buttons["First Button"].frame
    let sample = CGPoint(x: button.minX + 8, y: button.midY)
    guard let color = screenColor(at: sample) else {
      return XCTFail("截图取色失败")
    }
    XCTAssertEqual(
      nearestStyleName(to: color), "success",
      "alert 不是 success 样式:在 \(sample) 取到 rgb\(color),"
        + "而 success 应为 rgb(25, 135, 84)")
  }

  // MARK: - 验收行:三次快速点击只触发一次(SwiftyButton 防抖)

  /// 在**不遮挡屏幕**的那个按钮上验证防抖。
  ///
  /// 为什么不用主按钮:主按钮的回调是同步 addSubview 一个覆盖整个 window 的 alert,
  /// 第二、三次点击全都打在 alert 上,根本到不了按钮。那样"只触发一次"是遮挡的
  /// 结果,与 ignoreEventInterval 无关 —— 实测把主按钮的 ignoreEventInterval
  /// 设为 0(等于关掉防抖),三连击主按钮**依然**只记录到一次回调,
  /// 也就是说那样写出来的用例根本区分不了任何东西。
  /// DebounceButton 的回调只往 EventLog 记一行,三次点击都能真的送到按钮上。
  func testThreeRapidTapsFireHandlerOnlyOnce() {
    let button = app.buttons["DebounceButton"]
    XCTAssertTrue(button.waitForExistence(timeout: 10))

    // 三连击手势,而不是三次 tap():后者每次都要重新解析元素,很容易超出
    // ignoreEventInterval(默认 1.0s),那时"只触发一次"就不再是防抖的功劳。
    let start = Date()
    button.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertLessThan(
      elapsed, 1.0,
      "三次点击共用了 \(elapsed)s,已超过 SwiftyButton 默认的 1.0s 忽略窗口 —— "
        + "这一轮不构成对防抖的检验")

    waitUntil(10, "第一次点击的回调送达") {
      self.occurrences(of: "DebounceTap#1", in: self.eventLog) == 1
    }
    let log = eventLog
    XCTAssertEqual(
      occurrences(of: "DebounceTap#", in: log), 1,
      "三次快速点击送达了不止一次回调,防抖没生效。EventLog = \(log)")

    // 反面:忽略窗口过去之后,同一个按钮必须还能再触发 —— 否则上面那条
    // "只有一次"用一个坏掉的按钮也能满足。
    Thread.sleep(forTimeInterval: 1.2)
    button.tap()
    waitUntil(10, "忽略窗口过后再次点击可以送达") {
      self.occurrences(of: "DebounceTap#2", in: self.eventLog) == 1
    }
  }

  // MARK: - 验收行:Alert 的两个按钮各自执行自己的动作

  func testAlertButtonsRunTheirOwnActions() {
    XCTAssertTrue(mainButton.waitForExistence(timeout: 10))

    mainButton.tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    app.buttons["First Button"].firstMatch.tap()
    waitUntil(10, "第一个按钮的动作被执行") {
      self.occurrences(of: "First Button tapped", in: self.eventLog) == 1
    }
    XCTAssertEqual(
      occurrences(of: "Second button tapped", in: eventLog), 0,
      "只点了第一个按钮,第二个按钮的动作却也执行了。EventLog = \(eventLog)")

    // 等防抖窗口过去,再开一个新的 alert 验证第二个按钮
    waitUntil(10, "alert 关闭") { !self.alert.exists }
    waitUntil(15, "toast 队列排空(顺带让 1.0s 防抖窗口过去)") { !self.toast.exists }

    mainButton.tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    app.buttons["Second Button"].firstMatch.tap()
    waitUntil(10, "第二个按钮的动作被执行") {
      self.occurrences(of: "Second button tapped", in: self.eventLog) == 1
    }
    XCTAssertEqual(
      occurrences(of: "First Button tapped", in: eventLog), 1,
      "第一个按钮的动作被执行了不止一次。EventLog = \(eventLog)")
  }

  // MARK: - 验收行:Alert 关闭时执行 dismiss block

  func testAlertDismissBlockRuns() {
    XCTAssertTrue(mainButton.waitForExistence(timeout: 10))
    mainButton.tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    XCTAssertEqual(
      occurrences(of: "Alert Dismissed", in: eventLog), 0, "alert 还没关就执行了 dismiss block")

    app.buttons["First Button"].firstMatch.tap()

    waitUntil(10, "alert 从窗口移除") { !self.alert.exists }
    waitUntil(10, "dismiss block 被执行") {
      self.occurrences(of: "Alert Dismissed", in: self.eventLog) == 1
    }
  }

  // MARK: - 验收行:旋转设备,Toast 跟着朝向走

  /// 旋转后再出的 toast,必须落在**新朝向**窗口的底部中央。
  ///
  /// 这正是"SwiftyGlobal 是实时计算"的可观察含义:窗口尺寸若是启动时算好缓存起来的
  /// (1.x 的 static var,B17),横屏下拿到的仍是竖屏的 402×874,toast 会被放到
  /// 横屏窗口(874×402)之外。
  ///
  /// **不覆盖**"旋转过程中已经显示着的那一个 toast 会不会跟着动":XCUITest 设置
  /// 朝向时会等 App 空闲,而 toast 停留期间恒有一个 2.5s 的 alpha 动画在跑,
  /// 于是 orientation 的 setter 恰好在这个 toast 停留结束时才返回 —— 旋转做完,
  /// 这一个 toast 也正好该消失了。这条限制是结构性的,不是时序余量不够。
  /// 详见本轮报告。
  func testToastFollowsDeviceOrientation() {
    XCTAssertTrue(mainButton.waitForExistence(timeout: 10))

    // 竖屏基准
    mainButton.tap()
    XCTAssertTrue(toast.waitForExistence(timeout: 10))
    let portraitWindow = window.frame
    XCTAssertGreaterThan(portraitWindow.height, portraitWindow.width, "起始朝向不是竖屏")
    assertToastAnchoredToBottomCenter("竖屏")
    let portraitToast = toast.frame

    XCUIDevice.shared.orientation = .landscapeLeft
    // 必须等窗口**稳定**下来,不能只等 width > height:旋转动画进行中取到的
    // window.frame 是中间态(实测量到过 (-13, -300.8, 775.7, 568.9))。
    waitUntil(20, "窗口稳定为横屏") {
      let frame = self.window.frame
      return frame.origin == .zero
        && abs(frame.width - portraitWindow.height) < 1
        && abs(frame.height - portraitWindow.width) < 1
    }
    let landscapeWindow = window.frame

    showFreshToast()
    assertToastAnchoredToBottomCenter("横屏")
    XCTAssertNotEqual(
      portraitToast.origin, toast.frame.origin,
      "横屏与竖屏下的 toast 位置完全相同,说明位置没有跟着朝向重算")
    XCTAssertFalse(
      landscapeWindow.contains(portraitToast),
      "竖屏那份坐标在横屏窗口里仍然是合法位置,这一轮区分不出'实时计算'与'缓存'")
  }

  // MARK: - 验收行:带输入框的 Alert 会避让键盘

  func testAlertWithTextFieldAvoidsKeyboard() {
    XCTAssertTrue(mainButton.waitForExistence(timeout: 10))
    mainButton.tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 10))

    let field = app.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), "addTextField() 的输入框没出现")
    let title = app.staticTexts["Congratulations"]
    let fieldBefore = field.frame.origin.y
    let titleBefore = title.frame.origin.y

    field.tap()
    guard waitForKeyboardOnScreen() else {
      return XCTFail(
        "软件键盘没有出现在屏幕内。模拟器接着宿主机硬件键盘时键盘会被停靠到屏幕外,"
          + "此时本用例不成立 —— 用 Scripts/uitest.sh 运行,它会关掉硬件键盘。")
    }

    // 观察者是在 keyboardWillShow 里**同步**改 frame 的(没有动画),
    // 所以键盘一上屏,位移就已经完成。
    waitUntil(5, "alert 随键盘上移") { field.frame.origin.y < fieldBefore - 5 }
    let fieldDuring = field.frame.origin.y
    XCTAssertEqual(
      titleBefore - title.frame.origin.y, fieldBefore - fieldDuring, accuracy: 1.0,
      "alert 内部元素位移不一致,说明动的不是整个 contentView")
    XCTAssertTrue(alert.exists, "alert 在键盘弹出时被关掉了")

    // 点 alert 上方的背景收起键盘:SwiftyAlertView 的 tapped 手势会 endEditing,
    // 而 hideWhenBackgroundViewIsTapped 默认 false,alert 本身不会关。
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    waitUntil(10, "键盘收起") { self.app.keyboards.count == 0 }

    waitUntil(5, "alert 随键盘回到原位") { abs(field.frame.origin.y - fieldBefore) < 0.5 }
    XCTAssertEqual(title.frame.origin.y, titleBefore, accuracy: 0.5, "alert 没有回到原位")
    XCTAssertTrue(alert.exists, "收起键盘时 alert 被误关")
  }
}
