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

  /// 不传 identifier 时,add() 不能抹掉调用方自己设好的 op.name。
  ///
  /// add() 曾经无条件执行 `op.name = identifier`,不传就写成 nil,
  /// 之后按原名 remove / operation(withIdentifier:) 都找不到它。
  ///
  /// 判别力:改回无条件赋值,两条断言都失败。
  func testAddWithoutIdentifierKeepsExistingName() {
    pool.stop()
    let op = BlockOperation {}
    op.name = "mine"

    pool.add(op)

    XCTAssertEqual(op.name, "mine")
    XCTAssertTrue(pool.operation(withIdentifier: "mine") === op)
  }

  /// remove(withIdentifier:) 取消**全部**同名 operation。
  ///
  /// 它曾倒序找到第一个就 break,只取消了最后加入的那个:多条 Promise 链共用一个
  /// identifier 时只停下一条,其余照跑。
  ///
  /// 判别力:改回找到一个就 break,第一个 operation 不会被取消。
  func testRemoveByIdentifierCancelsEveryMatchingOperation() {
    pool.stop()
    let first = BlockOperation {}
    let second = BlockOperation {}
    let other = BlockOperation {}
    pool.add(first, withIdentifier: "same")
    pool.add(second, withIdentifier: "same")
    pool.add(other, withIdentifier: "other")

    XCTAssertTrue(pool.remove(withIdentifier: "same"))

    XCTAssertTrue(first.isCancelled, "先加入的同名 operation 也必须被取消")
    XCTAssertTrue(second.isCancelled)
    XCTAssertFalse(other.isCancelled, "不同名的不受影响")
  }

  /// remove(withIdentifier:) 的契约是:在 queue.operations 中按 name 找到匹配项并
  /// 对其调用 cancel(),找到返回 true、找不到返回 false。
  ///
  /// 用信号量把 operation 钉在"执行中"状态,使它必定还在 queue.operations 里,
  /// 从而不依赖队列并发宽度(maxThreadCount() = 2*activecpu-1,在多核机器上
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

  // MARK: - 生命周期

  /// 线程池实例必须能被释放。
  ///
  /// 曾经不能:init 里投递的常驻 RunLoop operation(`prepareEnvironment()`)
  /// 在闭包里**强引用 self**,而它的循环条件 `while !Thread.current.isCancelled`
  /// 永远不会成立 —— `op.cancel()` 置的是 *operation* 的标志位,不是线程的。
  /// 于是那个 operation 永不结束,对 self 的强引用永不解除,SwiftyThreadPool
  /// 因此**永远不会 deinit**;连带着 deinit 里那句针对 B18 的
  /// `removeObserver(memoryWarningObserver)` 也永远执行不到。
  ///
  /// 该 operation 已在本轮删除(它的 CFRunLoopSource 的 perform 回调是 nil,
  /// 被唤醒也什么都不做,且全仓库没有任何消费者;1.x 里它因为 B9 的赋值顺序
  /// 问题压根没入过队,删掉正好恢复 1.x 的可观察行为)。
  ///
  /// 判别力:把 prepareEnvironment() 与 init 里那次 add 加回去,本测试变红。
  func testPoolDeallocatesAfterCancel() {
    weak var weakPool: SwiftyThreadPool?

    autoreleasepool {
      let local = SwiftyThreadPool()
      weakPool = local
      local.cancel()
    }

    // operation 由队列异步释放,轮询等待而不是立即断言
    let deadline = Date().addingTimeInterval(5.0)
    while weakPool != nil && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    XCTAssertNil(
      weakPool,
      "SwiftyThreadPool 必须能被释放 —— 否则 deinit 里针对 B18 的观察者撤销永远执行不到")
  }

  // MARK: - B10 回归

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
