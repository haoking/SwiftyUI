import XCTest

@testable import SwiftyUI

final class SwiftyToastTests: XCTestCase {

  /// init 的主线程前置条件在主线程上不应触发。
  /// (无法测试它在后台线程确实 trap —— precondition 失败会终止测试进程。)
  func testInitOnMainThreadPassesPrecondition() {
    XCTAssertTrue(Thread.isMainThread)
    _ = SwiftyToast("precondition check")
    SwiftyToast.cancel()
  }

  /// 测试环境没有可用 window,构造 toast 不应崩溃(依赖 Task 10 的可选 keyWindow)。
  func testCreatingToastWithoutWindowDoesNotCrash() {
    _ = SwiftyToast("hello")
    SwiftyToast.cancel()
  }

  /// B8:连续创建多个 toast,队列状态不应损坏(本任务未修复 B8 本身,
  /// 这里只验证在当前单线程用法下 add/fire/finish 不会互相破坏状态)。
  func testMultipleToastsQueueSafely() {
    for index in 0..<10 {
      _ = SwiftyToast("toast-\(index)")
    }
    SwiftyToast.cancel()
  }
}
