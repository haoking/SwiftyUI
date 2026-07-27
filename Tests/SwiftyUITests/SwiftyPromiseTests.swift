import XCTest

@testable import SwiftyUI

private struct TestError: Error {}

final class SwiftyPromiseTests: XCTestCase {

  /// 记录执行顺序的线程安全收集器
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func record(_ item: String) {
      lock.lock()
      defer { lock.unlock() }
      items.append(item)
    }

    var snapshot: [String] {
      lock.lock()
      defer { lock.unlock() }
      return items
    }
  }

  // MARK: - 链式顺序

  func testThenChainRunsInOrder() {
    let recorder = Recorder()
    let done = expectation(description: "链条结束")

    Promise<Void>.firstly {
      recorder.record("1")
    }.then {
      recorder.record("2")
    }.then {
      recorder.record("3")
      done.fulfill()
    }.catch()

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(recorder.snapshot, ["1", "2", "3"])
  }

  func testThenCanHopToMainThread() {
    let done = expectation(description: "主线程任务执行")
    let ranOnMain = Box(false)

    Promise<Void>.firstly(on: .background) {
      // 后台
    }.then(on: .main) {
      ranOnMain.value = Thread.isMainThread
      done.fulfill()
    }.catch()

    wait(for: [done], timeout: 10.0)
    XCTAssertTrue(ranOnMain.value)
  }

  // MARK: - 值传递

  func testValuePropagatesAcrossThreads() {
    let done = expectation(description: "值传递")
    let received = Box<String?>(nil)

    Promise<String>.firstly(on: .background) { update, _ in
      update("abc")
    }.then { update, value in
      var v = value
      v?.append("def")
      update(v)
    }.then(on: .main) { _, value in
      received.value = value
      done.fulfill()
    }.catch()

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(received.value, "abcdef")
  }

  // MARK: - 错误短路

  func testErrorShortCircuitsRemainingTasks() {
    let recorder = Recorder()
    let caught = expectation(description: "错误被捕获")

    Promise<Void>.firstly {
      recorder.record("1")
    }.then {
      recorder.record("2")
      throw TestError()
    }.then {
      recorder.record("3-不应执行")
    }.catch { _ in
      recorder.record("catch")
      caught.fulfill()
    }

    wait(for: [caught], timeout: 10.0)
    XCTAssertFalse(
      recorder.snapshot.contains("3-不应执行"),
      "抛错之后的 then 不应执行")
  }

  // MARK: - B11 / B16 回归

  /// B11:always 必须在链条全部完成之后才执行。
  func testAlwaysRunsAfterChainCompletes() {
    let recorder = Recorder()
    let done = expectation(description: "always 执行")

    Promise<Void>.firstly {
      recorder.record("task1")
    }.then {
      recorder.record("task2")
    }.always {
      recorder.record("always")
      done.fulfill()
    }.catch { _ in }

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(
      recorder.snapshot, ["task1", "task2", "always"],
      "always 必须是最后一项(B11)")
  }

  /// B11:即使链条中途抛错,always 仍必须执行,且排在 catch 之后。
  func testAlwaysRunsAfterErrorShortCircuit() {
    let recorder = Recorder()
    let done = expectation(description: "always 执行")

    Promise<Void>.firstly {
      recorder.record("task1")
    }.then {
      throw TestError()
    }.then {
      recorder.record("不应执行")
    }.always {
      recorder.record("always")
      done.fulfill()
    }.catch { _ in
      recorder.record("catch")
    }

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(recorder.snapshot, ["task1", "catch", "always"])
  }

  /// B16:start() 可以在不提供错误处理的情况下启动链条。
  func testStartRunsChainWithoutCatch() {
    let recorder = Recorder()
    let done = expectation(description: "链条结束")

    Promise<Void>.firstly {
      recorder.record("task1")
    }.then {
      recorder.record("task2")
      done.fulfill()
    }.start()

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(recorder.snapshot, ["task1", "task2"])
  }

  /// 终结符只生效一次:重复调用 start(),或 start() 之后再 catch(),
  /// 都不能二次推进链条(否则同一条链上的两个任务会被并发投递)。
  func testTerminatorStartsChainOnlyOnce() {
    let recorder = Recorder()
    let done = expectation(description: "链条结束")

    let promise = Promise<Void>.firstly {
      // 故意慢一步:若链条被二次推进,task2 会抢在 task1 前面记录
      Thread.sleep(forTimeInterval: 0.1)
      recorder.record("task1")
    }.then {
      recorder.record("task2")
      done.fulfill()
    }

    promise.start()
    promise.start()
    promise.catch { _ in }

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(recorder.snapshot, ["task1", "task2"])
  }

  // MARK: - 生命周期

  /// 链条运行期间由已投递的 operation 持有 Promise,链条结束后必须释放:
  /// 既不能提前释放(链条跑不完),也不能留下循环引用。
  func testPromiseIsReleasedAfterChainCompletes() {
    weak var weakPromise: Promise<Void>?
    let done = expectation(description: "链条结束")

    autoreleasepool {
      // 调用方不持有任何引用,链条仍必须跑完
      let promise = Promise<Void>.firstly {
        // 后台
      }.then(on: .main) {
        done.fulfill()
      }
      weakPromise = promise
      promise.start()
    }

    wait(for: [done], timeout: 10.0)

    // operation 完成后由队列异步释放,轮询等待而不是立即断言
    let deadline = Date().addingTimeInterval(5.0)
    while weakPromise != nil && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    XCTAssertNil(weakPromise, "链条结束后 Promise 应被释放(不能有循环引用)")
  }

  // MARK: - B7 回归

  /// B7:并发地跑多条链,内部状态不应互相串扰。
  func testConcurrentChainsDoNotInterfere() {
    let iterations = 20
    let done = expectation(description: "全部链条结束")
    done.expectedFulfillmentCount = iterations

    let results = Recorder()

    for index in 0..<iterations {
      Promise<String>.firstly(on: .background) { update, _ in
        update("chain-\(index)")
      }.then { update, value in
        update((value ?? "") + "-step2")
      }.then(on: .main) { _, value in
        results.record(value ?? "nil")
        done.fulfill()
      }.start()
    }

    wait(for: [done], timeout: 30.0)

    let snapshot = results.snapshot
    XCTAssertEqual(snapshot.count, iterations)
    for index in 0..<iterations {
      XCTAssertTrue(
        snapshot.contains("chain-\(index)-step2"),
        "chain-\(index) 的值被串扰或丢失(B7)")
    }
  }
}
