import UIKit

/// 测试公用工具。所有测试图片都在内存中确定性生成,不依赖任何资源文件。
enum TestSupport {

  /// 生成一张纯色图片。
  static func makeSolidImage(
    color: UIColor,
    size: CGSize = CGSize(width: 32, height: 32)
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      color.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }

  /// 生成一张左右两色的图片,用于取色算法测试。
  /// 左半宽度占 40%,右半占 60%,因此右色是出现次数更多的一方。
  static func makeTwoToneImage(
    left: UIColor,
    right: UIColor,
    size: CGSize = CGSize(width: 100, height: 100)
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      left.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: size.width * 0.4, height: size.height))
      right.setFill()
      ctx.fill(CGRect(x: size.width * 0.4, y: 0, width: size.width * 0.6, height: size.height))
    }
  }

  /// 生成一张能判别 getColors() 排序方向的图片。
  ///
  /// getColors() 只在 x∈[5,10] 这一竖条内采样背景色,因此颜色差异必须发生在
  /// 垂直方向上才能被区分。本夹具让左侧竖条上部 70% 为 majorityEdge、
  /// 下部 30% 为 minorityEdge,于是"出现最多的边缘色"与"最少的"明确不同。
  ///
  /// 右侧填一个亮色,使 primary 不会因候选集为空而落到 fallback。
  static func makeEdgeDiscriminatingImage(
    majorityEdge: UIColor,
    minorityEdge: UIColor,
    body: UIColor,
    size: CGSize = CGSize(width: 250, height: 250)
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      body.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      let stripWidth = size.width * 0.2  // 覆盖 x∈[5,10] 采样区
      majorityEdge.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: stripWidth, height: size.height * 0.7))
      minorityEdge.setFill()
      ctx.fill(CGRect(x: 0, y: size.height * 0.7, width: stripWidth, height: size.height * 0.3))
    }
  }
}

/// 被等待的操作在限定时间内没有返回。
struct TestTimeoutError: Error, CustomStringConvertible {
  let seconds: Double
  var description: String { "操作在 \(seconds) 秒内未返回(疑似挂死)" }
}

/// 给一段 async 操作加超时:超时就抛错让测试变红,而不是把测试进程挂死。
///
/// 为什么需要它:`XCTestExpectation` + `wait(for:timeout:)` 只护得住同步测试;
/// async 测试里的 `await` 没有任何内建时限。而 `Promise.value()` 在链条无法
/// 终结时**永不返回、且不响应 Task 取消**(见 Sources/SwiftyPromise.swift 中
/// value() 的文档),所以这一类回归的失败模式是挂死而不是失败——挂死时唯一的
/// 兜底是 CI 的 job 级 timeout,而 Scripts/test.sh 只在 xcodebuild 退出**之后**
/// 才去 grep 日志,被杀掉时不产生任何诊断信息。
///
/// 为什么不用 `withThrowingTaskGroup` + 一个 sleep 子任务:task group 在闭包
/// 返回前会隐式等待**全部**子任务结束,而这里要防的恰恰是"body 永远不返回"
/// ——那样 group 自己就先挂住了,`cancelAll()` 也救不回来(同上:不响应取消)。
///
/// 因此改用两个 detached task 抢一个只能恢复一次的 continuation:谁先到谁胜出。
/// 超时分支恢复之后本函数立即返回,挂住的那个任务被留在原地——它不是本函数的
/// 子任务,不会阻塞返回,随测试进程退出而消失。
///
/// 为什么不用 `XCTestCase.executionTimeAllowance`:它只有在测试计划里开启
/// "Test Timeouts"(或给 xcodebuild 传 -test-timeouts-enabled)之后才生效,
/// 需要改动 Scripts/test.sh 与 CI 配置才能起作用;本地一个自包含的帮助函数
/// 无此依赖,失败信息也更具体。
func withTestTimeout<T: Sendable>(
  _ seconds: Double = 20,
  _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
  let once = TestOnce()
  return try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<T, any Error>) in
    let deadline = Task.detached {
      do {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      } catch {
        return  // 被取消:body 已经先返回了
      }
      if once.claim() {
        continuation.resume(throwing: TestTimeoutError(seconds: seconds))
      }
    }
    Task.detached {
      do {
        let value = try await body()
        if once.claim() { continuation.resume(returning: value) }
      } catch {
        if once.claim() { continuation.resume(throwing: error) }
      }
      deadline.cancel()
    }
  }
}

/// 只让第一个调用者胜出。与 Sources/SwiftyPromise.swift 里的 ResumeGuard 同型
/// ——那个是 private 的,跨模块用不了。
private final class TestOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !claimed else { return false }
    claimed = true
    return true
  }
}

/// 线程安全的单值容器,供测试从异步回调里回传结果。
///
/// 库里跨线程投递的回调(Promise 的任务闭包、UIImage.colors 的 complete)
/// 都是 @Sendable 的,直接捕获并改写一个局部 `var` 是真实的数据竞争
/// ——回调线程写、测试线程在 wait 之后读——严格并发检查会拒绝。
/// 加锁后语义不变,断言仍然成立。
final class Box<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ initial: Value) {
    storage = initial
  }

  var value: Value {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      storage = newValue
    }
  }
}

/// 测试里跨线程读写单个值的小盒子。
///
/// 与上面的 Box 的区别只在类型参数上:Box 要求 `Value: Sendable`,而取消测试
/// 要装的是 `Error?` —— `any Error` **不是** Sendable,`Box<Error?>` 根本编译
/// 不过。此处刻意不加约束:装进来的东西只在锁保护的临界区里交接,跨线程搬运
/// 的安全性由这把锁而不是类型系统提供。
///
/// @unchecked Sendable 的理由与库内的 ResumeGuard 一致:唯一的可变状态
/// 只经由 lock 保护的临界区读写,编译器无法验证,故为 unchecked。
final class Locked<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: T

  init(_ initial: T) { self.value = initial }

  func get() -> T {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ newValue: T) {
    lock.lock()
    defer { lock.unlock() }
    value = newValue
  }
}
