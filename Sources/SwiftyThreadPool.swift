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

  public static let defalut: SwiftyThreadPool = {
    return SwiftyThreadPool()
  }()

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
    // 必须先赋值再 add:add 内部通过 currentQueue 读取 queue,
    // 在赋值之前调用会导致 environment operation 被静默丢弃(B9)。
    // 此处直接写 self.queue、不经过 lock:实例尚未逃逸到其他线程,是安全的。
    self.queue = queue
    add(prepareEnvironment(), withIdentifier: "me.haoking.environmentOperation")

    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.removeAll()
    }
  }

  private func prepareEnvironment() -> BlockOperation {
    let environmentOperation: BlockOperation = BlockOperation.init {

      var context: CFRunLoopSourceContext = CFRunLoopSourceContext.init(
        version: 0, info: unsafeBitCast(self, to: UnsafeMutableRawPointer.self), retain: nil,
        release: nil, copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil,
        perform: nil)
      let runLoopSource: CFRunLoopSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
      let runLoop: CFRunLoop = RunLoop.current.getCFRunLoop()
      CFRunLoopAddSource(runLoop, runLoopSource, .defaultMode)
      while !Thread.current.isCancelled {
        _ = autoreleasepool {
          RunLoop.current.run(mode: RunLoop.Mode.default, before: Date.distantFuture)
        }
      }
    }
    return environmentOperation
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

  deinit {
    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    cancel()
  }
}
