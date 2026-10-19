import Synchronization
import XCTest

@testable import SwiftyUI

private struct TestError: Error {}

final class SwiftyPromiseTests: XCTestCase {

  /// 记录执行顺序的线程安全收集器
  private final class Recorder: Sendable {
    private let items = Mutex<[String]>([])

    func record(_ item: String) {
      items.withLock { $0.append(item) }
    }

    var snapshot: [String] {
      items.withLock { $0 }
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

  // 本节每一个 async 测试都把"可能挂起在 Promise 上"的那一段包进
  // withTestTimeout(见 TestSupport.swift)。绝大多数测试里那就是整个函数体。
  //
  // 原因:这些测试等的是 Promise.value(),而它在链条无法终结时永不返回、
  // 且不响应 Task 取消——一旦回归,失败模式是**挂死**而不是失败
  // (testAsyncValueAfterStartDoesNotHang 与 testAsyncValueCalledTwiceDoesNotHang
  // 保护的正是这类回归)。挂死时唯一的兜底是 CI 的 job 级 timeout,而
  // Scripts/test.sh 只在 xcodebuild 退出之后才 grep 日志,被杀掉时什么诊断
  // 信息都留不下。包上超时之后,同样的回归会在 20 秒内变成一条明确的失败。
  // 这条规则在本节内统一适用,新增 async 测试请照此办理。

  func testAsyncValueReturnsFinalValue() async throws {
    let value = try await withTestTimeout {
      try await Promise<String>.firstly(on: .background) { update, _ in
        update("abc")
      }.then { update, current in
        update((current ?? "") + "-def")
      }.value()
    }

    XCTAssertEqual(value, "abc-def")
  }

  func testAsyncValueThrowsChainError() async throws {
    do {
      _ = try await withTestTimeout {
        try await Promise<String>.firstly(on: .background) { _, _ in
          throw TestError()
        }.value()
      }
      XCTFail("应当抛出链条中的错误")
    } catch is TestError {
      // 期望路径
    }
  }

  func testAsyncValueOnVoidPromise() async throws {
    let recorder = Recorder()
    _ = try await withTestTimeout {
      try await Promise<Void>.firstly {
        recorder.record("task1")
      }.then {
        recorder.record("task2")
      }.value()
    }

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

  /// 注意:"调用方零桥接"这条性质由 MainActorConsumer.load() 的函数体本身证明
  /// (它是 @MainActor 隔离的,里面直接 `try await ....value()`,不做任何桥接),
  /// 与本测试用什么方式去驱动它无关。因此把驱动动作包进 withTestTimeout
  /// (闭包是非隔离的,对 consumer 的调用变成跨 actor 的 await)不会削弱判别力。
  @MainActor
  func testAsyncValueCallableFromMainActor() async throws {
    let consumer = MainActorConsumer()
    try await withTestTimeout { try await consumer.load() }
    XCTAssertEqual(consumer.received, "main-actor-value")
  }

  /// 出错路径上 always 与 catch 的 errorBlock 都会触发,靠 ResumeGuard
  /// 保证只恢复一次。单次运行不足以说明问题——若存在二次 resume,
  /// 进程会立刻因 SWIFT TASK CONTINUATION MISUSE 崩溃,因此跑 100 次
  /// 顺序调用,把"从未崩溃"当作证据的一部分。
  func testAsyncValueErrorPathNeverDoubleResumes() async throws {
    try await withTestTimeout {
      for _ in 0..<100 {
        do {
          _ = try await Promise<String>.firstly(on: .background) { _, _ in
            throw TestError()
          }.value()
          XCTFail("应当抛出链条中的错误")
        } catch is TestError {
          // 期望路径
        }
      }
    }
  }

  /// 并发跑多条会出错的链,让不同链之间的调度交织更复杂,
  /// 进一步放大二次 resume / continuation 泄漏可能暴露的窗口。
  func testAsyncValueErrorPathConcurrentStress() async throws {
    try await withTestTimeout {
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
  }

  /// 并发跑多条成功的链:既验证并发下取值互不串扰,也是对 always 闭包
  /// 改用强 self(而非 [weak self])这一决定的压力测试——如果强 self
  /// 的选择有问题,高并发、高频创建/释放 Promise 的场景更容易暴露竞态。
  func testAsyncValueConcurrentSuccessStress() async throws {
    try await withTestTimeout {
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
      // 只包住会挂起的这一句:下面的轮询本身已有 5 秒 deadline,不会挂死
      let value = try await withTestTimeout { try await promise.value() }
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
    let value = try await withTestTimeout {
      let promise = Promise<String>.firstly(on: .background) { update, _ in
        update("done")
      }
      promise.start()
      // 等链条确实跑完,确保下面的 value() 调用命中的是"已终结"分支,
      // 而不是"已启动但仍在飞行中"这条本来就正确的路径。
      try await Task.sleep(nanoseconds: 300_000_000)
      return try await promise.value()
    }
    XCTAssertEqual(value, "done")
  }

  /// 同一个问题的另一种触发方式:对同一个 Promise 连续调用两次 value()。
  /// 第一次调用 await 返回时链条必然已经终结,第二次调用必须走"已终结"
  /// 分支立即返回,而不是挂起。
  func testAsyncValueCalledTwiceDoesNotHang() async throws {
    let second = try await withTestTimeout {
      let promise = Promise<String>.firstly(on: .background) { update, _ in
        update("once")
      }
      _ = try await promise.value()
      return try await promise.value()
    }
    XCTAssertEqual(second, "once")
  }

  // MARK: - value() 与 catch(_:) 互不干扰(两种顺序都要成立)

  /// **顺序一:先 catch,再 value()。**
  ///
  /// `catch(_:)` 是替换语义;value() 曾经内部转手调用它,于是
  /// `p.catch { showError($0) }` 之后再 `try await p.value()`,showError 被静默
  /// 丢弃 —— 用户明明登记过错误处理器,却再也收不到错误。
  ///
  /// 判别力:把 registerValueWaiter 里那次内部槽位的登记改回 self.catch,最后那条
  /// 断言(先注册的处理器也必须收到错误)必然失败。头一段 do/catch 仍会通过,
  /// 因为 value() 自己的处理器活了下来 —— 这正是这个缺陷"静默"的地方。
  ///
  /// 首个任务故意慢 0.3 秒:必须让 value() 在链条**仍在飞行中**时登记处理器,
  /// 才会走到这条路径;链条若已终结,value() 走的是另一条(立即返回)分支。
  func testAsyncValuePreservesPreviouslyRegisteredCatchHandler() async throws {
    let caughtByCatch = Box(false)
    let promise = Promise<String>.firstly(on: .background) { _, _ in
      Thread.sleep(forTimeInterval: 0.3)
      throw TestError()
    }
    promise.catch { _ in caughtByCatch.value = true }

    do {
      _ = try await withTestTimeout { try await promise.value() }
      XCTFail("应当抛出链条中的错误")
    } catch is TestError {
      // 期望路径:value() 自己登记的处理器
    }

    XCTAssertTrue(
      caughtByCatch.value,
      "value() 之前登记的 catch 处理器必须照样收到错误,不能被 value() 覆盖掉")
  }

  /// 组合后两个处理器都必须被调用,且各只调用一次(组合不能变成重复调用)。
  func testAsyncValueErrorReachesBothHandlersExactlyOnce() async throws {
    let catchCallCount = Box(0)
    let promise = Promise<String>.firstly(on: .background) { _, _ in
      Thread.sleep(forTimeInterval: 0.3)
      throw TestError()
    }
    promise.catch { _ in catchCallCount.value += 1 }

    do {
      _ = try await withTestTimeout { try await promise.value() }
      XCTFail("应当抛出链条中的错误")
    } catch is TestError {
      // 期望路径
    }

    // markError 只会各调用一次两个槽位的处理器
    XCTAssertEqual(catchCallCount.value, 1, "先注册的处理器应恰好被调用一次")
  }

  /// **顺序二:先 value(),再 catch。**
  ///
  /// 上一个测试的镜像。`catch(_:)` 的替换语义若把 value() 装上的处理器顶掉,
  /// 链条出错时就没有人拿着那个错误去恢复 continuation;随后 fire() 走到
  /// .finish 分支,value() 挂上的那个 always 任务照样执行,于是这个 await
  /// **以 nil 正常返回,错误被整个吞掉** —— 不是挂死(实测确认,见报告)。
  /// 与顺序一是同一类静默丢失,只是丢的东西反过来:那边丢的是调用方的处理器,
  /// 这边丢的是错误本身,而后者连"出过错"都看不出来。
  ///
  /// 判别力(已实测):把 value() 里的处理器写回调用方的 errorBlock 槽位
  /// (无论是 `self.catch { ... }` 还是往 errorBlock 上追加),下面的
  /// `XCTFail("应当抛出链条中的错误")` 都会触发。
  ///
  /// 顺序控制:`value()` 在挂起**之前**就同步登记好自己的处理器
  /// (withCheckedThrowingContinuation 的闭包体是同步执行的),因此
  /// async let 起飞后等 0.2 秒再调 catch,足以保证"value 先、catch 后";
  /// 链条本身要 0.5 秒才抛错,两者都赶在它之前。
  func testCatchAfterValueReachesBothHandlers() async throws {
    let caughtByCatch = Box(false)
    let promise = Promise<String>.firstly(on: .background) { _, _ in
      Thread.sleep(forTimeInterval: 0.5)
      throw TestError()
    }

    async let awaited: String? = withTestTimeout { try await promise.value() }
    try await Task.sleep(nanoseconds: 200_000_000)
    promise.catch { _ in caughtByCatch.value = true }

    do {
      _ = try await awaited
      XCTFail("应当抛出链条中的错误")
    } catch is TestError {
      // 期望路径:value() 自己的处理器没有被 catch(_:) 顶掉
    }

    XCTAssertTrue(
      caughtByCatch.value,
      "value() 之后登记的 catch 处理器也必须收到错误")
  }

  // MARK: - value() 的登记窗口

  /// **登记与出错之间不允许有第三种交错。**
  ///
  /// 曾经"追加 always 任务"与"加挂内部错误处理器"是 value() 里两个**独立**的
  /// 临界区。链条若恰好在两者之间出错,markError 读到的 internalErrorHandler
  /// 还是 nil —— 这个错误抵达不了任何人;随后 fire() 的 .finish 分支照常跑
  /// value() 的 always 任务,以链条当时的值恢复 continuation。调用方拿到
  /// Optional(99) 正常返回,完全看不出出过错。可达条件不是理论上的:只要另一个
  /// 终结符已经把链条推进在飞就够了(start() 之后 value()、catch(_:) 之后
  /// value()、两个并发的 value())。
  ///
  /// 这个窗口窄到直接测必然靠运气(在两次调用之间插入 0.25 秒的 sleep,40/40
  /// 从"抛错"翻转成"返回 Optional(99)";不插则 40/40 正确)。所以这里不碰运气,
  /// 用 debugSetValueRegistrationHook 把"错误恰好落在登记边界上"这一格变成
  /// **确定命中**的:
  ///   1. 链条第二步阻塞在 gate 上 —— 不放行就不可能抛错,也就不可能抢在
  ///      value() 登记之前发生;
  ///   2. value() 走完登记之后钩子才放行 gate,并一直等到 markError 已经**读过**
  ///      处理器槽位才返回(errorBlock 是 markError 从槽位里读出来、在临界区外
  ///      调用的第一个处理器,它被调用即证明那次读取已经发生)。
  /// 于是错误确定地落在"登记刚刚结束"这一刻:
  ///   · 登记是一个临界区 —— 处理器早已在槽位里,markError 读得到,value() 抛
  ///     TestError;
  ///   · 登记是两个临界区 —— 钩子正落在两者之间,处理器还没挂上去,markError
  ///     读到 nil,value() 以 Optional(99) 正常返回。
  ///
  /// 判别力(已实测,见报告):把登记拆回 appendAlwaysIfUnfinished +
  /// addInternalErrorHandler 两个临界区,本测试确定性变红。
  func testValueRegistrationDoesNotSwallowConcurrentChainError() async throws {
    let pool = SwiftyThreadPool()
    let gate = DispatchSemaphore(value: 0)  // 放行链条抛错
    let slotsRead = DispatchSemaphore(value: 0)  // markError 已读过处理器槽位

    let promise = Promise<Int>.firstly(pool: pool, on: .background) { (update, _) in
      update(99)
    }.then(on: .background) { (_, _) in
      // 不放行就一直等:保证错误不可能发生在 value() 登记之前
      _ = gate.wait(timeout: .now() + 10)
      throw TestError()
    }

    // catch(_:) 在这里身兼两职:它是第一个终结符(让链条在 value() 之前就飞
    // 起来 —— 这正是本缺陷的可达条件),也是"markError 已经走出临界区"的信号。
    promise.catch { _ in slotsRead.signal() }

    promise.debugSetValueRegistrationHook {
      gate.signal()
      _ = slotsRead.wait(timeout: .now() + 10)
    }

    do {
      let value = try await withTestTimeout { try await promise.value() }
      XCTFail(
        "链条出错了,value() 却以 \(String(describing: value)) 正常返回 —— 错误被整个吞掉")
    } catch is TestError {
      // 期望路径
    }
  }

  /// **链条早已出错终结之后再调 value():必须重新抛出那个错误。**
  ///
  /// 2.1 之前错误对象根本没有被留下来,这条路径返回的是链条终结时的最后一个值
  /// (这里是 Optional(5))—— 调用方连"出过错"都看不出来,而 README 一直宣称
  /// 这里会抛。上一个测试关的是"出错与登记并发"那一路,这一个关的是"出错早已
  /// 尘埃落定"那一路,两者走的是同一个判断的两个分支。
  ///
  /// 时序不靠 sleep:always 任务是在 fire() 的 .finish 分支里投递的,那时
  /// isFinished 已经置位,所以 always 的任务体跑起来就证明链条确实终结了。
  ///
  /// 判别力(已实测,见报告):去掉登记临界区里 `if let error = self.error`
  /// 这一路(退回只判 isFinished),本测试变红。
  func testAsyncValueAfterSettledErrorRethrowsIt() async throws {
    let pool = SwiftyThreadPool()
    let settled = XCTestExpectation(description: "链条已终结")

    let promise = Promise<Int>.firstly(pool: pool, on: .background) { (update, _) in
      update(5)
    }.then(on: .background) { (_, _) in
      throw TestError()
    }.always {
      settled.fulfill()
    }
    promise.catch { _ in }

    await fulfillment(of: [settled], timeout: 20)

    do {
      let value = try await withTestTimeout { try await promise.value() }
      XCTFail(
        "链条是因为出错才终结的,value() 却返回了 \(String(describing: value)) —— 应当重新抛出那个错误")
    } catch is TestError {
      // 期望路径
    }
  }

  // MARK: - 取消(2.1)

  /// 链条中的任务在开始执行前被取消 → catch 收到 PromiseError.cancelled,
  /// 且后续任务不再执行。
  ///
  /// 2.0 的行为是:被取消的 operation 不执行自己的块就直接结束,
  /// completionBlock 照样推进 fire(),于是链条**跳过这一步、带着陈旧的值
  /// 继续跑完后续任务、最后以"成功"终结** —— 调用方完全看不出取消发生过。
  ///
  /// 全程在一个**独立**的线程池上进行:先挂起它,让 operation 排队但不开始,
  /// 再按 identifier 精确取消我们自己那一个,然后放行。不碰
  /// SwiftyThreadPool.default —— 那是进程级单例,动它会污染别的测试。
  ///
  /// 时序不靠 sleep:`catch(_:)` 是终结符,它同步走完
  /// beginIfNeeded() → fire() → task.start(on:),返回时第一个 operation 必然
  /// 已经排在池子里;而池子是挂起的,它不可能已经开始执行。下面的 remove
  /// 因此确定地命中"已排队、未开始"这一格,而不是碰运气。
  func testCancelledTaskFailsChainWithCancelledError() {
    let pool = SwiftyThreadPool()
    pool.stop()

    let secondTaskRan = Box(false)
    let received = Box<(any Error)?>(nil)
    let settled = XCTestExpectation(description: "chain settles")

    let promise = Promise<Int>.firstly(pool: pool, with: "first", on: .background) { (update, _) in
      update(1)
    }.then(on: .background) { (_, _) in
      secondTaskRan.value = true
    }

    promise.catch { error in
      received.value = error
      settled.fulfill()
    }

    // 此时第一个 operation 已排队在挂起的池里。精确取消它。
    XCTAssertTrue(pool.remove(withIdentifier: "first"), "应当找到并取消排队中的第一个 operation")
    pool.restart()

    wait(for: [settled], timeout: 20)
    XCTAssertEqual(
      received.value as? PromiseError, .cancelled,
      "被取消的任务必须让链条以 PromiseError.cancelled 失败")
    XCTAssertFalse(secondTaskRan.value, "链条已因取消而终结,后续任务不得执行")
  }

  /// 取消发生在执行**期间**时,工作其实已经完成 —— 不得因此丢弃有效结果。
  ///
  /// 与上一个测试是对称的一对,各钉住判定的一个方向:上一个钉"取消抢在执行
  /// 前面 → 链条必须失败",这一个钉"取消输给了执行 → 链条不许失败"。删掉
  /// fire() 里整个 if 块,上一个红;删掉 `!flag.didRun` 这半个条件,这一个红。
  ///
  /// 但有一件事必须说白,免得后来者以为这里的覆盖比实际更严:
  /// `op?.isCancelled == true` 这半个条件**没有任何测试钉得住**,单独把它删成
  /// `if !flag.didRun`,整个套件依然全绿。这不是覆盖缺口,而是一个等价变异 ——
  /// BlockOperation 的执行块只有在被取消时才会不执行,所以在 completionBlock
  /// 里 `!didRun` 与 `isCancelled && !didRun` 恒等价,没有任何输入能区分两者。
  /// 保留 isCancelled 的理由是把"我们判的是取消"这个意图写进代码,并且在将来
  /// 执行块万一多出别的提前返回路径时结论依然成立;它是一条靠人维持的性质,
  /// 不要指望改动它会有测试报警。
  ///
  /// 时序不靠 sleep:removeAll() 在任务体**内部**调用,此时本 operation 还在
  /// queue.operations 里(尚未 finish),因此必然把正在执行的自己一起 cancel
  /// —— 确定命中"取消发生在执行期间"这一格。update(42) 已经完整执行。
  func testCancelDuringExecutionDoesNotDiscardCompletedWork() async throws {
    let pool = SwiftyThreadPool()

    let promise = Promise<Int>.firstly(pool: pool, on: .background) { (update, _) in
      update(42)
      // 任务体跑完之后才取消:BlockOperation 的块不检查 isCancelled,
      // 所以这份工作是完整完成的,不该因为一个迟到的 cancel 被丢弃。
      pool.removeAll()
    }

    let value = try await withTestTimeout { try await promise.value() }
    XCTAssertEqual(value, 42, "取消发生在执行期间时工作已完成,结果不得被丢弃")
  }

  /// 上一个测试走的是 operationBuildT(两参 `(update, value)` 闭包);这一个走
  /// **非泛型的 operationBuild**(零参闭包)—— 也就是 README 与 iOSExample 实际
  /// 演示的那种写法。
  ///
  /// 为什么不是重复:两条构建路径各自 new 一个 RunFlag、各自写一句
  /// `flag.markRun()`,互不相干。只删掉 operationBuild 里的那一句(泛型那条
  /// 保持不动),在没有本测试时全套 115 个测试照样全绿 —— 而漏掉的正是
  /// "执行期间被取消 → 已完成的工作被当作取消丢弃"这个缺陷在公开 API 最常见
  /// 写法上的复现。一对刻意对称的判定,不能只测其中一半的输入路径。
  ///
  /// 时序与上一个同理:removeAll() 在任务体内部调用,必然把正在执行的自己一起
  /// 取消。后面那个 then 是 removeAll() 之后才入队的新 operation,不在被取消之列,
  /// 它写入的 7 必须能被完整取回 —— 既证明链条没被判成失败,也证明它继续往下走了。
  func testCancelDuringExecutionOnNonGenericTaskDoesNotDiscardWork() async throws {
    let pool = SwiftyThreadPool()

    let promise = Promise<Int>.firstly(pool: pool) {
      pool.removeAll()
    }.then(on: .background) { (update, _) in
      update(7)
    }

    let value = try await withTestTimeout { try await promise.value() }
    XCTAssertEqual(
      value, 7,
      "非泛型任务在执行期间被取消时,链条不得失败,后续任务必须照常执行")
  }

  /// fire() 的 `.finish` 分支必须把 always 任务投递到**注入的池**上,
  /// 不能落回 SwiftyThreadPool.default。
  ///
  /// `.run` 分支的池路由已经被本节第一个测试钉住了(它若落到 .default,那个测试
  /// 就取消不到自己的 operation,只能超时变红);`.finish` 分支在本测试之前
  /// 没有任何覆盖 —— 把它改成 `task.start(on: .default)`,全套 115 个测试全绿。
  ///
  /// 这不是洁癖。value() 追加的那个 always operation 走的正是 `.finish` 分支,
  /// 后续任务要在它上面判定取消;若它其实安静地待在 .default 上、而测试取消的
  /// 是注入的池,那个测试就会在什么都没验证的情况下通过 —— 本仓库已经有过
  /// 七个这样的测试,不能再添一个。
  ///
  /// 判据不涉及任何时序:正在执行的 operation 尚未 finish,仍留在
  /// queue.operations 里,因此它必然能在自己所属的那个池里按 identifier 找到自己。
  func testAlwaysTasksAreDispatchedToInjectedPool() {
    let pool = SwiftyThreadPool()
    let foundItselfInInjectedPool = Box<Bool?>(nil)
    let done = expectation(description: "always 执行")

    Promise<Void>.firstly(pool: pool) {
      // 主体不做事,只为把链条推到 .finish 分支
    }.always(with: "always-op") {
      foundItselfInInjectedPool.value = pool.operation(withIdentifier: "always-op") != nil
      done.fulfill()
    }.start()

    wait(for: [done], timeout: 20)
    XCTAssertEqual(
      foundItselfInInjectedPool.value, true,
      "always 任务必须投递到注入的池上,不能落回 SwiftyThreadPool.default")
  }

  /// value() 的 always 任务被取消时必须**返回链条的最终值**,而不是永久挂死。
  ///
  /// 2.0 的行为:value() 把"恢复 continuation"这件事整个放进一个 always 任务里。
  /// 那个 operation 一旦在开始执行前被取消,它的执行块就不运行,ResumeGuard
  /// 永远不会被 claim —— `try await promise.value()` 就永久挂在那里,没有任何
  /// 超时、也不响应 Task 取消。SwiftyThreadPool 收到内存告警就会 removeAll(),
  /// 所以这在真机上够得着。
  ///
  /// 为什么断言的是"返回值"而不是"抛 .cancelled":能走到 onCancelled 就说明
  /// 链条**成功**终结了。每一条错误路径上 markError 都严格先于 fire() 的
  /// .finish,内部错误处理器必定早已抢到 ResumeGuard;而登记与出错之间没有第三
  /// 种交错(见 testValueRegistrationDoesNotSwallowConcurrentChainError),所以
  /// onCancelled 一旦抢到 claim,currentValue 就是最终且正确的值。此时抛
  /// `.cancelled` 等于把一个已经算好的正确结果丢掉去报一个"取消",与本次发布
  /// 在链条任务上采纳的 `isCancelled && !didRun` 恰好背道而驰 —— 那条判定的
  /// 全部理由就是"迟到的取消不该丢弃已经完成的工作"。
  ///
  /// 断言从"抛错"改成"返回值",判别力没有丢:这个测试真正钉住的是**不挂死**。
  /// 删掉 value() 传给 .create 的 `onCancelled:` 参数,本测试仍然以 10 秒超时
  /// 变红(已实测,见报告)。
  ///
  /// 构造上有一个必须守住的点:链条本身要**成功**终结,只取消 value() 那一个
  /// always 任务。若让链条出错,markError 会经 internalErrorHandler **抢先**恢复
  /// continuation,onCancelled 根本没有机会参与 —— 那就完全没测到要测的东西。
  /// 做法是把链条任务放到
  /// .main 上(完全不经线程池),always 默认在 .background(经池),于是挂起的
  /// 池里排着的**只有** value() 那个 always 任务,removeAll() 取消的也只有它。
  ///
  /// 时序不靠 sleep 一个魔法时长,而是轮询 `pool.count` 等它真的排进池里。
  /// 这里不能改用轮询 Promise 内部的 alwaysTasks:那个数组在 fire() 走到
  /// .finish 时就被排空并转交给池,它非空的窗口是"已 append、链条尚未终结",
  /// 恰恰在 always 任务进池**之前**。实测下来 .main 上那一步跑得比 10ms 的
  /// 轮询间隔还快,该计数恒为 0(轮询会一直空转到 deadline);而即使侥幸读到
  /// 非 0,那时 always 任务还没进池,removeAll() 什么也取消不到。pool.count
  /// 观察的才是本测试真正依赖的那个事件。
  ///
  /// 必须包 withTestTimeout:这条路径回归时的表现就是挂死,不加超时的话
  /// 测试会挂住整个测试进程而不是失败 —— 那正是要防的东西。
  ///
  /// 这个测试顺带钉住了另一件事:value() 的 always 任务必须投递到**注入的池**
  /// 上。它若落回 SwiftyThreadPool.default,下面 removeAll() 取消的就不是它,
  /// 本测试会以超时变红。
  func testAsyncValueReturnsValueWhenItsAlwaysTaskIsCancelled() async throws {
    let pool = SwiftyThreadPool()
    pool.stop()  // always 任务会排队但不开始

    let promise = Promise<Int>.firstly(pool: pool, on: .main) { (update, _) in
      update(1)
    }

    let waiter = Task { try await withTestTimeout(10) { try await promise.value() } }

    // 等链条把 .main 上的任务跑完、并把 always 任务投递到(挂起的)池里。
    let deadline = Date().addingTimeInterval(5)
    while pool.count == 0 && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(
      pool.count, 1,
      "value() 的 always 任务应当已排在这个挂起的池里;为 0 说明它根本没进这个池")

    XCTAssertTrue(pool.removeAll(), "应当取消到排队中的 always 任务")
    // 这行是必需的,不是收尾清理:取消本身不会让 operation 结束,是队列**跑到**
    // 它才让它结束的。挂起的 OperationQueue 不会 finish 任何 operation(包括
    // 已被取消的),completionBlock 因此不触发,onCancelled 也就不会被调用 ——
    // 删掉这行,即便修复在位,本测试也会以 10 秒超时失败。
    pool.restart()

    do {
      let value = try await waiter.value
      XCTAssertEqual(
        value, 1,
        "always 任务被取消时链条已经成功终结,value() 必须返回它的最终值")
    } catch is TestTimeoutError {
      XCTFail("value() 挂死了 —— 正是本次要修的回归")
    } catch {
      XCTFail("链条成功终结,value() 不应抛错:\(error)")
    }
  }

  // MARK: - 终结后追加 then/always(issue #4)

  /// 链条终结后,追加任务必须被拒绝。
  ///
  /// 直接测内部的 appendTaskIfUnfinished / appendAlwaysIfUnfinished,而不是
  /// 调 then {} —— 后者在 debug 下会 assertionFailure 中止整个测试进程。
  /// 断言的是"拒绝"这个 release 与 debug 都成立的部分。
  func testAppendingAfterTerminationIsRejected() async throws {
    let pool = SwiftyThreadPool()
    let promise = Promise<Int>.firstly(pool: pool, on: .background) { (update, _) in
      update(1)
    }
    _ = try await withTestTimeout { try await promise.value() }
    // 此时链条已终结

    XCTAssertFalse(
      promise.debugAppendTaskAccepted(),
      "链条终结后追加链条任务必须被拒绝")
    XCTAssertFalse(
      promise.debugAppendAlwaysAccepted(),
      "链条终结后追加 always 任务必须被拒绝")
  }

  /// 反面对照:链条尚未终结时,追加必须被接受。
  /// 没有这一条,上面那个测试在"永远返回 false"的实现下也会绿。
  func testAppendingBeforeTerminationIsAccepted() {
    let pool = SwiftyThreadPool()
    pool.stop()  // 不让它真的跑起来,链条保持未终结
    defer { pool.restart() }

    let promise = Promise<Int>.firstly(pool: pool, on: .background) { (update, _) in
      update(1)
    }

    XCTAssertTrue(promise.debugAppendTaskAccepted(), "链条未终结时追加必须被接受")
    XCTAssertTrue(promise.debugAppendAlwaysAccepted(), "链条未终结时追加必须被接受")
  }
}
