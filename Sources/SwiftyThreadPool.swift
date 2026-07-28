//
//  SwiftyTask.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/10/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public final class SwiftyThreadPool: @unchecked Sendable {
  private var MAX_THREAD_COUNT: Int {
    var activecpu: UInt32 = 0
    var size = MemoryLayout<UInt32>.size
    sysctlbyname("hw.activecpu", &activecpu, &size, nil, 0)
    let avaliableCount: Int = 2 * Int(activecpu) - 1
    let result: Int = avaliableCount > 3 ? avaliableCount : 3
    return result
  }

  public static let `default`: SwiftyThreadPool = {
    return SwiftyThreadPool()
  }()

  @available(
    *, deprecated, renamed: "default",
    message: "拼写错误,2.0 起改为 default。旧名将在下个大版本移除。"
  )
  public static var defalut: SwiftyThreadPool { `default` }

  // 保护 queue 这个可选变量本身。OperationQueue 自身线程安全,
  // 但 cancel() 会把它置 nil,与其他线程的读取构成竞争。
  private let lock = NSLock()
  private var queue: OperationQueue?

  private var currentQueue: OperationQueue? {
    lock.lock()
    defer { lock.unlock() }
    return queue
  }

  // NotificationCenter 的 block 形式返回一个 token 作为观察者,
  // self 从未被注册,因此 removeObserver(self) 不会移除任何东西(B18)。
  private var memoryWarningObserver: (any NSObjectProtocol)?

  // internal(而非 private)以便单元测试构造独立实例,避免测试间通过单例互相污染。
  // 对外仍只暴露静态单例访问器。
  init() {
    let queue: OperationQueue = OperationQueue()
    queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
    // 必须先赋值再做任何投递:add 内部通过 currentQueue 读取 queue,在赋值
    // 之前调用会被静默丢弃 —— 1.x 就是这样把常驻 RunLoop operation 丢掉的(B9)。
    // 那个 operation 已在 2.0 删除(理由见下方 deinit 的说明),但这条赋值顺序
    // 的约束依然成立:init 里今后若再要投递任何 operation,必须排在这一行之后。
    // 此处直接写 self.queue、不经过 lock:实例尚未逃逸到其他线程,是安全的。
    self.queue = queue

    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.removeAll()
    }
  }

  /// 添加一个 operation 到队列。
  ///
  /// 注意:`cancel()` 会把内部队列置为 nil;在那之后调用 `add` 会被
  /// 静默丢弃 —— 不会抛错、不会返回值、也没有任何日志。调用方需要自行
  /// 保证不在 `cancel()` 之后继续 `add`。
  public func add(_ op: Operation, withIdentifier identifier: String? = nil) {
    guard let queue = currentQueue else { return }
    op.name = identifier
    queue.addOperation(op)
    queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
  }

  @discardableResult
  public func remove(withIdentifier identifier: String) -> Bool {
    var removed = false
    guard let queue = currentQueue else { return removed }
    for (_, op) in queue.operations.enumerated().reversed() {
      if op.name == identifier {
        op.cancel()
        removed = true
        queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
        break
      }
    }
    return removed
  }

  @discardableResult
  public func removeAll() -> Bool {
    var removed = false
    guard let queue = currentQueue else { return removed }
    if !queue.operations.isEmpty {
      for (_, op) in queue.operations.enumerated().reversed() {
        op.cancel()
      }
      queue.cancelAllOperations()
      removed = true
    }
    return removed
  }

  public func operation(withIdentifier identifier: String) -> Operation? {
    var tagOp: Operation?
    guard let queue = currentQueue else { return tagOp }
    for (_, op) in queue.operations.enumerated().reversed() {
      if op.name == identifier {
        tagOp = op
        break
      }
    }
    return tagOp
  }

  public var count: Int {
    guard let queue = currentQueue else { return 0 }
    return queue.operationCount
  }

  /// 队列是否处于挂起状态。
  public var isSuspended: Bool {
    return currentQueue?.isSuspended ?? false
  }

  /// 挂起队列。已经开始执行的 operation 会跑完,尚未开始的会等到 restart()。
  public func stop() {
    currentQueue?.isSuspended = true
  }

  /// 恢复队列。
  public func restart() {
    currentQueue?.isSuspended = false
  }

  public func cancel() {
    removeAll()
    lock.lock()
    queue = nil
    lock.unlock()
  }

  /// 2.0 删除了 1.x 的 `prepareEnvironment()` —— 一个在 init 里投递、跑一个
  /// 常驻 RunLoop 的 BlockOperation。删除的理由,按重要性排:
  ///
  /// 1. **它让本类型永远无法 deinit。** 那个闭包强引用 self,而循环条件
  ///    `while !Thread.current.isCancelled` 永远不会成立:`op.cancel()` 置的是
  ///    *operation* 的标志位,不是线程的。operation 因此永不结束,对 self 的
  ///    强引用永不解除 —— 下面这个 deinit(以及其中针对 B18 的观察者撤销)
  ///    从来就执行不到。回归测试:testPoolDeallocatesAfterCancel。
  /// 2. **它白占一条线程。** 池子的并发下限是 3,被它永久占去一条。
  /// 3. **它什么也没做。** 那个 CFRunLoopSource 的 `perform` 回调是 nil,
  ///    即使被唤醒也不会执行任何东西;全仓库没有任何代码往它上面投递工作。
  /// 4. **删掉恰好恢复 1.x 的可观察行为。** 1.x 里这次 add 排在
  ///    `self.queue = queue` **之前**,`guard let queue = currentQueue` 直接失败,
  ///    这个 operation 从来没有真正入过队。是 B9 修正了赋值顺序之后,它才第一次
  ///    跑起来 —— 也才第一次开始造成上面 1/2 两条危害。
  deinit {
    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    cancel()
  }
}
