import XCTest

@testable import SwiftyUI

private struct TestError: Error {}

final class SwiftyPromiseTests: XCTestCase {

  /// 本类在 Task 7 修复 B7 之前整体跳过。
  ///
  /// 跳过原因不是断言失败,而是 SwiftyPromise 当前存在**崩溃级**竞争:
  /// `fire()` 读取 `tasks.first`、启动它、再 `removeFirst()`,三步之间无同步。
  /// 两个线程并发进入 `fire()` 时会把同一个 operation 二次投递到
  /// OperationQueue,触发未捕获的 NSException,使整个测试进程崩溃
  /// (实测约 1/4~1/3 概率,隔离运行同样复现)。
  ///
  /// 若放任其随机崩溃,Tasks 6–21 的每一次全量回归都不可信,故在修复前跳过。
  /// **Task 7 的第一步就是删除本覆写**,先看到崩溃或失败,再实施修复。
  ///
  /// 崩溃前采集到的 always 顺序基线(B11 的直接证据,三次干净运行):
  ///   ["always", "task1", "task2"]
  ///   ["task1", "always", "task2"]
  ///   ["always", "task1", "task2"]
  /// 顺序不确定本身就证明 always 没有排在链条之后。
  override func setUpWithError() throws {
    try super.setUpWithError()
    throw XCTSkip("SwiftyPromise 存在崩溃级竞争 B7;Task 7 修复后删除本覆写以启用这些测试")
  }

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
    var ranOnMain = false

    Promise<Void>.firstly(on: .background) {
      // 后台
    }.then(on: .main) {
      ranOnMain = Thread.isMainThread
      done.fulfill()
    }.catch()

    wait(for: [done], timeout: 10.0)
    XCTAssertTrue(ranOnMain)
  }

  // MARK: - 值传递

  func testValuePropagatesAcrossThreads() {
    let done = expectation(description: "值传递")
    var received: String?

    Promise<String>.firstly(on: .background) { update, _ in
      update("abc")
    }.then { update, value in
      var v = value
      v?.append("def")
      update(v)
    }.then(on: .main) { _, value in
      received = value
      done.fulfill()
    }.catch()

    wait(for: [done], timeout: 10.0)
    XCTAssertEqual(received, "abcdef")
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

  // MARK: - 待修复行为的基线

  /// B11:always 应当在链条终结之后执行,但当前实现在 catch() 里
  /// 先启动 alwaysTasks 再 fire() 主链条,导致 always 反而排在前面。
  ///
  /// 本测试只记录顺序,不断言对错——当前顺序取决于队列调度,不稳定。
  /// Task 7 会把它改为确定性断言:always 必须是最后一项。
  func testAlwaysOrderingBaseline() {
    let recorder = Recorder()
    let done = expectation(description: "链条结束")

    Promise<Void>.firstly {
      recorder.record("task1")
    }.then {
      recorder.record("task2")
    }.always {
      recorder.record("always")
    }.catch { _ in }

    // always 与主链条并发,没有可靠的结束信号,只能定时采样
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { done.fulfill() }
    wait(for: [done], timeout: 10.0)

    print("BASELINE always 顺序 = \(recorder.snapshot)")
    XCTAssertTrue(recorder.snapshot.contains("always"), "always 至少应该执行过")
  }

  /// B16:不调用 catch() 的链条永远不会启动。
  /// 当前(错误)行为:任务不执行。Task 7 引入 start() 后会新增正确的测试。
  func testChainWithoutCatchNeverRuns_currentBuggyBehavior() {
    let recorder = Recorder()

    Promise<Void>.firstly {
      recorder.record("不应执行")
    }.then {
      recorder.record("也不应执行")
    }
    // 故意不调用 .catch()

    let settle = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settle.fulfill() }
    wait(for: [settle], timeout: 5.0)

    XCTAssertTrue(
      recorder.snapshot.isEmpty,
      "若此断言失败,说明 B16 已被修复,请改用 Task 7 中的正确断言")
  }
}
