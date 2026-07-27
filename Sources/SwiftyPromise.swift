//
//  SwiftyPromise.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/14/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import Foundation

public enum ThreadPerform: Int {
  case main
  case background
}

private struct PromiseTask {
  var identifier: String?
  var perform: ThreadPerform
  var op: Operation

  private init(_ identifier: String? = nil, _ perform: ThreadPerform = .background, _ op: Operation)
  {
    self.identifier = identifier
    self.perform = perform
    self.op = op
  }

  static func create(
    _ identifier: String? = nil, _ perform: ThreadPerform = .background, _ op: Operation
  ) -> PromiseTask {
    return PromiseTask(identifier, perform, op)
  }

  func start() {
    switch perform {
    case .main:
      OperationQueue.main.addOperation(op)
    case .background:
      // 拼写错误的 defalut 要到 Task 12 才改名,本 Task 保持现状
      SwiftyThreadPool.defalut.add(op, withIdentifier: identifier)
    }
  }
}

/// fire() 在临界区内算出的下一步动作。
/// 放在文件作用域而不是 fire() 内部:Swift 不允许在泛型函数里嵌套类型声明。
private enum PromiseNext {
  case run(PromiseTask)
  case finish([PromiseTask])
  case nothing
}

public final class Promise<T> {
  /// 保护下方全部可变状态。所有临界区都很短,串行队列足够,不需要更复杂的方案。
  private let stateQueue = DispatchQueue(label: "me.haoking.SwiftyPromise.state")

  private var tasks: [PromiseTask] = []
  private var alwaysTasks: [PromiseTask] = []
  private var errorBlock: ((Error) -> Void)?
  private var isError: Bool = false
  private var isStarted: Bool = false
  private var isFinished: Bool = false
  private var value: T?

  // MARK: - 状态访问(全部经由 stateQueue)

  private func withState<R>(_ body: () -> R) -> R {
    return stateQueue.sync(execute: body)
  }

  private func markError(_ error: Error) {
    // errorBlock 是用户代码,可能回头访问本 Promise,故取出后在临界区外调用
    let handler: ((Error) -> Void)? = withState {
      self.isError = true
      return self.errorBlock
    }
    handler?(error)
  }

  private func update(_ newValue: T?) {
    withState { self.value = newValue }
  }

  private var currentValue: T? {
    return withState { self.value }
  }

  // MARK: - 任务构建

  private func operationBuild(_ work: (() throws -> Void)?) -> Operation {
    // 这里不持有 self:链条运行期间的强引用由 fire() 在投递时挂到
    // operation 的 completionBlock 上,详见 fire()
    return BlockOperation { [weak self] in
      guard let self = self else { return }
      do {
        try work?()
      } catch {
        self.markError(error)
      }
    }
  }

  private func operationBuildT(
    _ work: @escaping (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Operation {
    return BlockOperation { [weak self] in
      guard let self = self else { return }
      do {
        try work(self.update, self.currentValue)
      } catch {
        self.markError(error)
      }
    }
  }

  // MARK: - 构造

  // init 期间还没有第二个线程能看到 self,直接写 tasks 是安全的
  private init(
    _ identifier: String? = nil, _ perform: ThreadPerform = .background,
    _ work: (() throws -> Void)?
  ) {
    tasks.append(.create(identifier, perform, operationBuild(work)))
  }

  private init(
    _ identifier: String? = nil, _ perform: ThreadPerform = .background,
    work: @escaping (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) {
    tasks.append(.create(identifier, perform, operationBuildT(work)))
  }

  @discardableResult
  public class func firstly(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (() throws -> Void)?
  ) -> Promise {
    return Promise(identifier, perform, work)
  }

  @discardableResult
  public class func firstly(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    work: @escaping (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    return Promise(identifier, perform, work: work)
  }

  // MARK: - 链式

  @discardableResult
  public func then(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (() throws -> Void)?
  ) -> Promise {
    withState { tasks.append(.create(identifier, perform, operationBuild(work))) }
    return self
  }

  @discardableResult
  public func then(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    work: @escaping (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    withState { tasks.append(.create(identifier, perform, operationBuildT(work))) }
    return self
  }

  @discardableResult
  public func always(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (() throws -> Void)?
  ) -> Promise {
    // always 的 operation 不参与 fire() 链条,完成后无需推进;
    // 此时链条已终结,再抛错也无处可去,直接吞掉
    let operation = BlockOperation { _ = try? work?() }
    withState { alwaysTasks.append(.create(identifier, perform, operation)) }
    return self
  }

  // MARK: - 终结

  /// 启动链条。不提供错误处理时使用;链条必须被终结,否则永远不会执行。
  public func start() {
    beginIfNeeded()
  }

  /// 启动链条,并在出错时回调。
  public func `catch`(_ errorBlock: ((Error) -> Void)? = nil) {
    withState { self.errorBlock = errorBlock }
    beginIfNeeded()
  }

  /// 终结只生效一次:重复调用 start()/catch(),或两者都调用,都不会二次推进链条
  /// ——否则两次 fire() 会并发跑同一条链上的两个任务。
  private func beginIfNeeded() {
    let shouldFire: Bool = withState {
      guard !isStarted else { return false }
      isStarted = true
      return true
    }
    guard shouldFire else { return }
    fire()
  }

  // MARK: - 推进

  private func fire() {
    // 决策全部在一个临界区里完成(取出任务的同时就把它移出队列),
    // 动作则放到临界区之外。两个线程因此不可能拿到同一个 task,
    // 也就不会把同一个 operation 二次投递(B7)。
    let next: PromiseNext = withState {
      guard !isFinished else { return .nothing }

      if isError {
        // 出错:丢弃剩余任务,直接进入终结
        tasks.removeAll()
        isFinished = true
        let pending = alwaysTasks
        alwaysTasks.removeAll()
        return .finish(pending)
      }

      if let task = tasks.first {
        tasks.removeFirst()
        return .run(task)
      }

      // 正常跑完
      isFinished = true
      let pending = alwaysTasks
      alwaysTasks.removeAll()
      return .finish(pending)
    }

    switch next {
    case .run(let task):
      // 已投递的 operation 是链条运行期间对 self 的唯一强引用:调用方不持有
      // Promise 时链条也能跑完。它不构成循环引用——task 在上面的临界区里已被
      // 移出 tasks,operation 完成后由队列释放,强引用随之解除。
      task.op.completionBlock = { self.fire() }
      task.start()
    case .finish(let pending):
      // always 在链条终结之后才执行(B11)
      for task in pending {
        task.start()
      }
    case .nothing:
      break
    }
  }
}
