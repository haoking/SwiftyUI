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

  // MARK: - B9 / B10 回归

  /// B9:常驻 RunLoop 的 environment operation 必须在 init 时真正入队。
  func testEnvironmentOperationIsEnqueued() {
    XCTAssertNotNil(
      pool.operation(withIdentifier: "me.haoking.environmentOperation"),
      "常驻 RunLoop operation 应在 init 时入队(B9)"
    )
  }

  /// B10:stop() 必须真的挂起队列。
  func testStopSuspendsQueue() {
    pool.stop()
    XCTAssertTrue(pool.isSuspended)

    // 用反向 expectation 而不是捕获一个 `var ran`:后者会在 operation 所在线程
    // 写、在测试线程读,本身就是数据竞争(严格并发检查会直接报出来)。
    // isInverted 的语义完全等价:0.5 秒内一旦执行就失败。
    let ran = expectation(description: "stop() 之后新加入的 operation 不应执行(B10)")
    ran.isInverted = true
    pool.add(BlockOperation { ran.fulfill() })
    wait(for: [ran], timeout: 0.5)
  }

  /// B10:restart() 必须恢复队列,并让挂起期间积压的 operation 跑起来。
  func testRestartResumesQueue() {
    pool.stop()

    let ran = expectation(description: "restart 之后积压任务执行")
    pool.add(BlockOperation { ran.fulfill() })

    pool.restart()
    XCTAssertFalse(pool.isSuspended)
    wait(for: [ran], timeout: 5.0)
  }
}
