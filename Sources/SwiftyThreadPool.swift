//
//  SwiftyThreadPool.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/10/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import Foundation
import UIKit

public final class SwiftyThreadPool: @unchecked Sendable {
  /// 并发上限:2 × hw.activecpu − 1,下限 3。建池时算一次 —— 它曾是计算属性,
  /// 每次 add() 都调一遍 sysctlbyname 并重设并发数。
  private static func maxThreadCount() -> Int {
    var activecpu: UInt32 = 0
    var size = MemoryLayout<UInt32>.size
    sysctlbyname("hw.activecpu", &activecpu, &size, nil, 0)
    return max(2 * Int(activecpu) - 1, 3)
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
    queue.maxConcurrentOperationCount = Self.maxThreadCount()
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
  /// 传了 `identifier` 就把它写进 `op.name`,之后可以按它 remove / 查找;不传则保留
  /// `op.name` 原有的值。
  ///
  /// 注意:`cancel()` 会把内部队列置为 nil;在那之后调用 `add` 会被
  /// 静默丢弃 —— 不会抛错、不会返回值、也没有任何日志。调用方需要自行
  /// 保证不在 `cancel()` 之后继续 `add`。
  public func add(_ op: Operation, withIdentifier identifier: String? = nil) {
    // 投递也在锁内完成,与 cancel() 的"取出并置 nil"互斥:否则可能在 cancel() 取消完
    // 之后,才把 op 投进那个即将被丢弃的队列,它就不会被取消。
    // addOperation 不会同步回调本类型,持锁调用没有重入问题。
    lock.lock()
    defer { lock.unlock() }
    guard let queue else { return }
    if let identifier { op.name = identifier }
    queue.addOperation(op)
  }

  /// 取消队列里**全部** name 等于 `identifier` 的 operation。
  ///
  /// 返回是否找到了至少一个。注意"找到"不等于"拦下了":尚未开始的 operation 不会再执行,
  /// 但已经在执行的 BlockOperation 不看 isCancelled,会照常跑完。
  @discardableResult
  public func remove(withIdentifier identifier: String) -> Bool {
    guard let queue = currentQueue else { return false }
    var removed = false
    for op in queue.operations where op.name == identifier {
      op.cancel()
      removed = true
    }
    return removed
  }

  @discardableResult
  public func removeAll() -> Bool {
    var removed = false
    guard let queue = currentQueue else { return removed }
    if !queue.operations.isEmpty {
      queue.cancelAllOperations()
      removed = true
    }
    return removed
  }

  public func operation(withIdentifier identifier: String) -> Operation? {
    var tagOp: Operation?
    guard let queue = currentQueue else { return tagOp }
    for op in queue.operations.reversed() where op.name == identifier {
      tagOp = op
      break
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
    // 取出与置 nil 在同一个临界区里完成,再取消取出来的那个队列。曾经是先 removeAll()
    // 再加锁置 nil,两步之间 add() 进来的 op 落进被丢弃的队列,却没被取消。
    lock.lock()
    let detached = queue
    queue = nil
    lock.unlock()
    detached?.cancelAllOperations()
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
