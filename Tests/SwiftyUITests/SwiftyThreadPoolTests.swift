import XCTest

@testable import SwiftyUI

final class SwiftyThreadPoolTests: XCTestCase {

  /// 每个测试用独立实例,避免污染全局单例
  private var pool: SwiftyThreadPool!

  override func setUp() {
    super.setUp()
    pool = SwiftyThreadPool()
  }

  override func tearDown() {
    pool.cancel()
    pool = nil
    super.tearDown()
  }

  // MARK: - 基本操作

  func testAddedOperationExecutes() {
    let done = expectation(description: "operation 执行")
    pool.add(BlockOperation { done.fulfill() })
    wait(for: [done], timeout: 5.0)
  }

  func testOperationLookupByIdentifier() {
    let blocker = expectation(description: "operation 开始")
    let release = expectation(description: "允许 operation 结束")

    pool.add(
      BlockOperation {
        blocker.fulfill()
        _ = XCTWaiter.wait(for: [release], timeout: 5.0)
      }, withIdentifier: "test.op")

    wait(for: [blocker], timeout: 5.0)
    XCTAssertNotNil(pool.operation(withIdentifier: "test.op"))
    XCTAssertNil(pool.operation(withIdentifier: "test.nonexistent"))
    release.fulfill()
  }

  /// remove(withIdentifier:) 的契约是:在 queue.operations 中按 name 找到匹配项并
  /// 对其调用 cancel(),找到返回 true、找不到返回 false。
  ///
  /// 用信号量把 operation 钉在"执行中"状态,使它必定还在 queue.operations 里,
  /// 从而不依赖队列并发宽度(MAX_THREAD_COUNT = 2*activecpu-1,在多核机器上
  /// 高达数十,靠单个 blocker 制造背压是不可靠的)。
  func testRemoveByIdentifierCancelsMatchingOperation() {
    let started = expectation(description: "target 开始执行")
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }

    let target = BlockOperation()
    target.addExecutionBlock {
      started.fulfill()
      release.wait()
    }
    pool.add(target, withIdentifier: "target")
    wait(for: [started], timeout: 5.0)

    // 仍在执行中,因此仍在 queue.operations 中,应能被找到并取消
    XCTAssertTrue(pool.remove(withIdentifier: "target"))
    XCTAssertTrue(target.isCancelled, "remove 应对匹配的 operation 调用 cancel()")

    // 未知标识符应返回 false
    XCTAssertFalse(pool.remove(withIdentifier: "no-such-operation"))
  }

  // MARK: - 待修复行为的基线

  /// B9:常驻 RunLoop 的 environment operation 应当在 init 时入队,
  /// 但当前实现在 `self.queue = queue` 之前就调用了 add,导致它从未入队。
  ///
  /// 当前(错误)行为:查不到该 operation。Task 6 会把断言翻转为 XCTAssertNotNil。
  func testEnvironmentOperationIsMissing_currentBuggyBehavior() {
    XCTAssertNil(
      pool.operation(withIdentifier: "me.haoking.environmentOperation"),
      "若此断言失败,说明 B9 已被修复,请改用 Task 6 中的正确断言"
    )
  }

  /// B10:stop() 与 restart() 的实现颠倒了。
  /// stop() 本应挂起队列(isSuspended = true),当前却设为 false。
  ///
  /// 当前(错误)行为:调用 stop() 之后,新加入的 operation 仍然会执行。
  /// Task 6 会把断言翻转。
  func testStopDoesNotActuallyStop_currentBuggyBehavior() {
    pool.stop()

    let ran = expectation(description: "stop 之后 operation 仍然执行了")
    pool.add(BlockOperation { ran.fulfill() })

    wait(for: [ran], timeout: 5.0)
    // 能走到这里就说明 stop() 没有真的停住队列 —— 这正是 B10
  }
}
