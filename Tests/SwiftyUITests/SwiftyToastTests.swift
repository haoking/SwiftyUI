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
}
