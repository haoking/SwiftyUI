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

  // MARK: - async 桥接

  func testAsyncValueReturnsFinalValue() async throws {
    let value = try await Promise<String>.firstly(on: .background) { update, _ in
      update("abc")
    }.then { update, current in
      update((current ?? "") + "-def")
    }.value()

    XCTAssertEqual(value, "abc-def")
  }

  func testAsyncValueThrowsChainError() async {
    do {
      _ = try await Promise<String>.firstly(on: .background) { _, _ in
        throw TestError()
      }.value()
      XCTFail("应当抛出链条中的错误")
    } catch {
      XCTAssertTrue(error is TestError)
    }
  }

  func testAsyncValueOnVoidPromise() async throws {
    let recorder = Recorder()
    _ = try await Promise<Void>.firstly {
      recorder.record("task1")
    }.then {
      recorder.record("task2")
    }.value()

    XCTAssertEqual(recorder.snapshot, ["task1", "task2"])
  }

  /// 模拟一个只能在主 actor 上访问状态的调用方(例如视图模型)。
  /// value() 是面向调用方的 API——Task 17 的教训是曾验证过"库内零桥接"
  /// 却没验证"调用方零桥接",这里补上那一面:在 MainActor 隔离方法里
  /// 直接 await value() 并把结果写回 MainActor 隔离的属性,不做任何桥接。
  /// 如果 value() 的实现悄悄要求调用方处于某个特定隔离域,这里会在编译期
  /// 报错,而不是留到某个消费者的 App 里才发现。
  @MainActor
  private final class MainActorConsumer {
    var received: String?

    func load() async throws {
      received = try await Promise<String>.firstly(on: .background) { update, _ in
        update("main-actor-value")
      }.value()
    }
  }

  @MainActor
  func testAsyncValueCallableFromMainActor() async throws {
    let consumer = MainActorConsumer()
    try await consumer.load()
    XCTAssertEqual(consumer.received, "main-actor-value")
  }

  /// 出错路径上 always 与 catch 的 errorBlock 都会触发,靠 ResumeGuard
  /// 保证只恢复一次。单次运行不足以说明问题——若存在二次 resume,
  /// 进程会立刻因 SWIFT TASK CONTINUATION MISUSE 崩溃,因此跑 100 次
  /// 顺序调用,把"从未崩溃"当作证据的一部分。
  func testAsyncValueErrorPathNeverDoubleResumes() async throws {
    for _ in 0..<100 {
      do {
        _ = try await Promise<String>.firstly(on: .background) { _, _ in
          throw TestError()
        }.value()
        XCTFail("应当抛出链条中的错误")
      } catch {
        XCTAssertTrue(error is TestError)
      }
    }
  }

  /// 并发跑多条会出错的链,让不同链之间的调度交织更复杂,
  /// 进一步放大二次 resume / continuation 泄漏可能暴露的窗口。
  func testAsyncValueErrorPathConcurrentStress() async {
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<50 {
        group.addTask {
          do {
            _ = try await Promise<String>.firstly(on: .background) { _, _ in
              throw TestError()
            }.value()
            XCTFail("应当抛出链条中的错误")
          } catch {
            XCTAssertTrue(error is TestError)
          }
        }
      }
    }
  }

  /// 并发跑多条成功的链:既验证并发下取值互不串扰,也是对 always 闭包
  /// 改用强 self(而非 [weak self])这一决定的压力测试——如果强 self
  /// 的选择有问题,高并发、高频创建/释放 Promise 的场景更容易暴露竞态。
  func testAsyncValueConcurrentSuccessStress() async {
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<50 {
        group.addTask {
          do {
            let value = try await Promise<String>.firstly(on: .background) { update, _ in
              update("chain-\(index)")
            }.then { update, current in
              update((current ?? "") + "-done")
            }.value()
            XCTAssertEqual(value, "chain-\(index)-done")
          } catch {
            XCTFail("不应抛错: \(error)")
          }
        }
      }
    }
  }

  /// value() 内部让 always 闭包强引用 self——这是防御性的写法(见
  /// Sources/SwiftyPromise.swift 中 value() 的注释),会构成一个瞬态的
  /// 自引用环。这里验证这个环不是永久的:链条终结后 Promise 应当仍能
  /// 被释放。
  func testAsyncValuePromiseIsReleasedAfterCompletion() async throws {
    weak var weakPromise: Promise<String>?

    do {
      let promise = Promise<String>.firstly(on: .background) { update, _ in
        update("abc")
      }
      weakPromise = promise
      let value = try await promise.value()
      XCTAssertEqual(value, "abc")
    }

    // RunLoop.current.run(until:) 在 async 上下文里不可用,改用 Task.sleep
    // 轮询;每次挂起/恢复都会跨越一次 Swift 并发运行时自己的 autorelease
    // 边界,足以让上面 do 块结束后失去的最后一个强引用被真正释放。
    let deadline = Date().addingTimeInterval(5.0)
    while weakPromise != nil && Date() < deadline {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertNil(weakPromise, "value() 完成后 Promise 应被释放(不能有循环引用)")
  }

  /// 审查发现:value() 在链条已经被别的终结符终结之后调用会永久挂起
  /// ——always() 无条件追加而不查 isFinished,catch() 的 beginIfNeeded()
  /// 在 isStarted 已置位时直接返回,fire() 便不会再被触发,append 进去的
  /// always 任务永远不会被排空。这与既有契约矛盾:
  /// testTerminatorStartsChainOnlyOnce 明确断言重复终结符是良性的。
  ///
  /// 这里覆盖"先 start(),链条跑完之后再 value()"的场景。
  func testAsyncValueAfterStartDoesNotHang() async throws {
    let promise = Promise<String>.firstly(on: .background) { update, _ in
      update("done")
    }
    promise.start()
    // 等链条确实跑完,确保下面的 value() 调用命中的是"已终结"分支,
    // 而不是"已启动但仍在飞行中"这条本来就正确的路径。
    try await Task.sleep(nanoseconds: 300_000_000)
    let value = try await promise.value()
    XCTAssertEqual(value, "done")
  }

  /// 同一个问题的另一种触发方式:对同一个 Promise 连续调用两次 value()。
  /// 第一次调用 await 返回时链条必然已经终结,第二次调用必须走"已终结"
  /// 分支立即返回,而不是挂起。
  func testAsyncValueCalledTwiceDoesNotHang() async throws {
    let promise = Promise<String>.firstly(on: .background) { update, _ in
      update("once")
    }
    _ = try await promise.value()
    let second = try await promise.value()
    XCTAssertEqual(second, "once")
  }
}
