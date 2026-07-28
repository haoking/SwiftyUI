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
