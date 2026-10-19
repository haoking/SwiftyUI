import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyToastTests: XCTestCase {

  /// SwiftyToast 是 @MainActor 隔离的,在主 actor 上构造应当正常工作。
  ///
  /// 2.0 早期靠 `precondition(Thread.isMainThread)` 做运行时检查,切到 Swift 6
  /// 语言模式后该约束改由编译器静态强制(从非隔离上下文调用 `SwiftyToast(_:)`
  /// 直接编译失败),precondition 已删除,因此这里也无法、也无需再测"后台线程
  /// 会不会 trap"——那种调用现在根本无法通过编译。
  func testInitOnMainActorSucceeds() {
    XCTAssertTrue(Thread.isMainThread)
    _ = SwiftyToast("main actor check")
    SwiftyToast.cancel()
  }

  /// accessibilityIdentifier 必须能从**非隔离**上下文读到。
  ///
  /// 这个常量存在的意义就是给 UI 自动化用,而那类代码通常是非隔离的。
  /// SwiftyToast 是 @MainActor 隔离的类型,成员默认继承这份隔离,于是从非隔离
  /// 上下文引用它会直接**编译失败**:
  ///     error: main actor-isolated class property 'accessibilityIdentifier'
  ///     can not be referenced from a nonisolated context
  /// —— 一个"为被外部识别而设"的常量,外部却写不出它的名字。
  ///
  /// 判别力:去掉源码里的 `nonisolated`,本方法编译不过,整个测试 target 都跑不起来。
  /// 这是编译期的红,不是运行期的红 —— 但正因为缺陷本身就是编译期的,
  /// 这里也只能这么锁。本方法特意声明为 nonisolated,不能跟着类型走主 actor。
  nonisolated func testAccessibilityIdentifierIsUsableFromNonisolatedContext() {
    XCTAssertEqual(SwiftyToast.accessibilityIdentifier, "SwiftyToast")
  }

  /// 测试环境没有可用 window,构造 toast 不应崩溃(依赖 Task 10 的可选 keyWindow)。
  func testCreatingToastWithoutWindowDoesNotCrash() {
    _ = SwiftyToast("hello")
    SwiftyToast.cancel()
  }

  /// B22 的另一半:几何必须在 show() 里算,不能在 init 里算。
  ///
  /// SwiftyToastCenter 是串行队列,一个 toast 要播满约 3.5s。在这期间创建的
  /// toast 只是排队,要等前面播完才轮到 show() —— 构造时算好的帧到那时早已过期
  /// (排队期间转屏、或构造时还没有 key window)。详见 SwiftyToast.layoutView(in:)。
  ///
  /// 本进程正是"没有 key window"那一面的天然夹具:
  /// `UIApplication.shared.connectedScenes` 为空,keyWindow 恒为 nil。
  ///
  /// 判别力:把 layoutView 挪回 init(1.x 与 2.0 早期的写法),
  /// containerSize 退化成 .zero,算出来的 x、y 都是负数,本断言立刻变红。
  func testGeometryIsNotComputedAtConstructionTime() {
    XCTAssertNil(SwiftyGlobal.keyWindow, "前提:测试进程没有 key window,否则本测试无判别力")

    let toast = SwiftyToast("geometry must wait for a window")
    defer { SwiftyToast.cancel() }

    XCTAssertEqual(
      toast.toastLabel.frame, .zero,
      "构造 toast 不应算帧 —— 帧必须等到 show() 拿到真实窗口那一刻才算,"
        + "否则排队期间转屏、或构造时无窗口,都会让 toast 以过期几何上屏(B22)")
  }

  /// 已经挂在窗口上的 toast,窗口尺寸一变要自己重新贴回底部中央。
  ///
  /// **本测试锁的是 mask 的语义,不是"真机旋转"这条完整链路。**
  /// 断言 `autoresizingMask == [...]` 那种写法只是把源码里的常量抄一遍,
  /// 换成别的 mask 一样能通过,没有判别力;这里改成让窗口真的换一次 bounds
  /// (旋转时 UIKit 对 window 做的正是这件事),看 label 自己有没有跟过去。
  /// 一个"看起来合理但其实不对"的 mask(例如 .flexibleWidth)会在这里露馅。
  ///
  /// 覆盖不到的那一段:真机旋转时这份 mask 会不会被应用到 window 的直接子视图、
  /// 以及那一刻 toast 是否确实还挂在 window 上。3.0 之前 XCUITest 也够不到 ——
  /// 设 XCUIDevice.orientation 会等 App 空闲,而 toast 停留期间恒有动画在跑;
  /// 3.0 起停留改成了真正的等待,但 UI 测试仍只验证旋转之后新出的 toast(见
  /// iOSExampleUITests.testToastFollowsDeviceOrientation 的说明)。
  ///
  /// 判别力:删掉源码里那行 autoresizingMask,label 原地不动,
  /// midX 与底边距两条断言都变红。
  func testToastLabelReanchorsItselfWhenWindowResizes() {
    let toast = SwiftyToast("autoresizing")
    defer { SwiftyToast.cancel() }

    let portrait = CGSize(width: 402, height: 874)
    let landscape = CGSize(width: 874, height: 402)
    let labelSize = CGSize(width: 120, height: 27)
    let bottomMargin: CGFloat = 30

    // 本进程没有 key window,show() 上不了屏;手工搭一个窗口,把 label 放到
    // layoutView(in:) 在竖屏下会算出的那个位置。
    let window = UIWindow(frame: CGRect(origin: .zero, size: portrait))
    let label = toast.toastLabel
    label.frame = CGRect(
      x: (portrait.width - labelSize.width) * 0.5,
      y: portrait.height - (labelSize.height + bottomMargin),
      width: labelSize.width, height: labelSize.height)
    window.addSubview(label)

    window.bounds = CGRect(origin: .zero, size: landscape)
    window.layoutIfNeeded()

    XCTAssertEqual(
      label.frame.midX, landscape.width * 0.5, accuracy: 1.0,
      "窗口变宽后 toast 必须仍然水平居中(实得 \(label.frame))")
    XCTAssertEqual(
      landscape.height - label.frame.maxY, bottomMargin, accuracy: 1.0,
      "窗口变矮后 toast 必须仍然贴着底边(实得 \(label.frame))")
    XCTAssertTrue(
      CGRect(origin: .zero, size: landscape).contains(label.frame),
      "toast 落到了窗口外,用户什么也看不到(实得 \(label.frame))")
  }

  /// B8:连续创建多个 toast,队列状态不应损坏。
  /// (B8 已由 SwiftyToastCenter 的 @MainActor 隔离修复 —— 队列只可能在主 actor
  /// 上被读写,不再有并发访问。)
  func testMultipleToastsQueueSafely() {
    for index in 0..<10 {
      _ = SwiftyToast("toast-\(index)")
    }
    SwiftyToast.cancel()
  }
}
