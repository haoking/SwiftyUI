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
      SwiftyThreadPool.default.add(op, withIdentifier: identifier)
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

/// 一条可链式组合的异步任务链。
///
/// - `T: Sendable`:链条会把 T 在线程之间搬运(某个任务里 `update(...)` 写入,
///   后续任务可能在另一个线程读出),因此 T 必须能安全跨线程。
/// - `@unchecked Sendable`:下方全部可变状态一律经 `withState`(即
///   `stateQueue.sync`)读写,线程安全由这把串行队列保证 —— 编译器无法验证
///   这一点,故为 unchecked。与 ImageCachePool、SwiftyThreadPool 同一模式。
public final class Promise<T: Sendable>: @unchecked Sendable {
  /// 保护下方全部可变状态。所有临界区都很短,串行队列足够,不需要更复杂的方案。
  private let stateQueue = DispatchQueue(label: "me.haoking.SwiftyPromise.state")

  private var tasks: [PromiseTask] = []
  private var alwaysTasks: [PromiseTask] = []
  private var errorBlock: (@Sendable (Error) -> Void)?
  private var isError: Bool = false
  private var isStarted: Bool = false
  private var isFinished: Bool = false
  private var value: T?

  // MARK: - 状态访问(全部经由 stateQueue)

  private func withState<R>(_ body: () -> R) -> R {
    return stateQueue.sync(execute: body)
  }

  private func markError(_ error: Error) {
    // errorBlock 是用户代码,可能回头访问本 Promise,故取出后在临界区外调用。
    // 也正因为在临界区外,它跑在"出错的那个 operation 所在的线程"上
    // (.background 时是 SwiftyThreadPool,.main 时是 OperationQueue.main),
    // 所以 errorBlock 必须是 @Sendable 的 —— 详见 catch(_:) 的说明。
    let handler: (@Sendable (Error) -> Void)? = withState {
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

  private func operationBuild(_ work: (@Sendable () throws -> Void)?) -> Operation {
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
    _ work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
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
    _ work: (@Sendable () throws -> Void)?
  ) {
    tasks.append(.create(identifier, perform, operationBuild(work)))
  }

  private init(
    _ identifier: String? = nil, _ perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) {
    tasks.append(.create(identifier, perform, operationBuildT(work)))
  }

  @discardableResult
  public class func firstly(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
  ) -> Promise {
    return Promise(identifier, perform, work)
  }

  @discardableResult
  public class func firstly(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    return Promise(identifier, perform, work: work)
  }

  // MARK: - 链式

  @discardableResult
  public func then(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
  ) -> Promise {
    withState { tasks.append(.create(identifier, perform, operationBuild(work))) }
    return self
  }

  @discardableResult
  public func then(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    withState { tasks.append(.create(identifier, perform, operationBuildT(work))) }
    return self
  }

  @discardableResult
  public func always(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
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
  ///
  /// - Important: `errorBlock` 在**抛出错误的那个任务所在的线程**上执行,
  ///   而不是调用 `catch(_:)` 的线程 —— 因此它是 @Sendable(非隔离)的。
  ///   在 @MainActor 上下文里写的闭包字面量会隐式带上主 actor 隔离,若不加这个
  ///   标注,`promise.catch { self.label.text = ... }` 会被静默地放到后台线程执行,
  ///   而调用点是同步的、不跨隔离,编译器无从察觉。要在错误处理里碰 UI,
  ///   请自行跳回主 actor。
  /// - Important: 本方法是**替换**语义 —— 它登记的是"这条链的错误处理器",
  ///   重复调用后者覆盖前者,传 nil 则清空。库内部需要在不破坏调用方已登记
  ///   处理器的前提下加挂自己的处理器时,走 addErrorHandler(_:) 而不是这里。
  public func `catch`(_ errorBlock: (@Sendable (Error) -> Void)? = nil) {
    withState { self.errorBlock = errorBlock }
    beginIfNeeded()
  }

  /// 追加一个错误处理器,而不是替换已有的那个。出错时按注册顺序全部调用。
  ///
  /// `catch(_:)` 是替换语义,库内部不能拿它当"加挂"用:调用方完全可能先
  /// `p.catch { showError($0) }` 再 `try await p.value()`,若 value() 内部转手调
  /// 一次 catch(_:),那个已经登记过的处理器就被静默丢弃了 —— 而 value() 的
  /// 另一条(已终结)分支恰恰在注释里明确拒绝调用 catch(_:),给出的理由
  /// 就是"会把已经注册过的 errorBlock 覆盖掉"。
  ///
  /// 读旧值与写组合值必须在同一个临界区内完成:先读后写会让两个并发的追加
  /// 互相覆盖,只是把竞争窗口缩小而不是消除 —— 与 appendAlwaysIfUnfinished
  /// 同一条理由。
  private func addErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) {
    withState {
      guard let existing = self.errorBlock else {
        self.errorBlock = handler
        return
      }
      self.errorBlock = { error in
        existing(error)
        handler(error)
      }
    }
  }

  /// 终结链条并以 await 取回最终值。
  ///
  /// 与 start() / catch(_:) 一样,本方法也是终结符。但重复终结对它是良性
  /// 的:调用时如果链条已经终结过(无论是被更早一次 start()、catch(_:)
  /// 还是 value() 调用终结的),本方法不会像 then()/always() 那样把回调
  /// 静默丢进一个不会再被处理的队列里、把调用方永远挂起——而是立即以链条
  /// 终结时的最后一个值返回。即便链条当初是因为出错才终结的,这种情况下
  /// 也**不会**重新抛出那个错误(错误对象本身没有被保留下来),而是照样
  /// 返回最后的值。
  ///
  /// - Important: 没有任何任务调用过 update(...) 时,返回值是 nil——
  ///   `Promise<Void>.value()` 因此恒为 nil,不是 `()`。
  /// - Important: 这个 await **不响应** Swift Task 的取消:所在 Task 被
  ///   取消后,本方法仍会一直等到链条终结才返回或抛错。
  /// - Important: 如果链条本身永远无法终结(例如 SwiftyThreadPool 被
  ///   cancel()/stop() 导致后续 operation 不再执行),本方法也永远不会
  ///   返回。
  public func value() async throws -> T? {
    return try await withCheckedThrowingContinuation { continuation in
      // 用一个 box 保证 continuation 只被恢复一次:链条正常结束与出错
      // 互斥,但两条路径都会走到这里——出错时 markError 先调用下面的
      // errorBlock,随后 fire() 仍会把 always 当作终结的一部分执行到,
      // ResumeGuard 保证先到者胜出(详见 markError 与 fire() 的顺序:
      // markError 在抛错任务的主体里同步完成,严格早于该任务的
      // completionBlock 触发的下一次 fire())。
      let resumed = ResumeGuard()

      let alwaysOperation = BlockOperation {
        // 强引用 self,不用 [weak self]——这是防御性的,不是纠正性的:
        // self 是这次正在进行的 async 调用(value() 本身)的接收者,按
        // Swift 的调用约定,在整个 await 期间(包括跨越挂起点)都会被
        // 保留,所以这里就算改成弱引用,self 也不会真的变成 nil。出错
        // 路径上更是如此:下面这行 guard 严格先于任何 self 的解引用
        // 执行,claim 失败时根本不会碰 self。保留强引用只是让"这里不
        // 依赖 self 的生死"这件事更直白,不必依赖上面这层不太显眼的
        // 调用约定论证。
        //
        // 这确实构成一个瞬态的自引用环(self -> alwaysTasks 或下面的
        // pending -> PromiseTask.op -> 这个闭包 -> self),但只要链条能
        // 到达 fire() 的 .finish 分支(正常跑完、出错终结都算),就会
        // 确定性打破:fire() 把 alwaysTasks 转交给目标队列并清空自己的
        // 引用,任务跑完后队列释放 Operation,环随之断开(回归测试见
        // testAsyncValuePromiseIsReleasedAfterCompletion)。如果链条根本
        // 到不了 .finish(见上面 value() 文档注释的第三条),这个环连同
        // 整条链一起泄漏——但这不是本方法引入的新风险,start()/catch()
        // 面对同一种情形也一样跑不完。
        guard resumed.claim() else { return }
        continuation.resume(returning: self.currentValue)
      }

      // 注册与"链条是否已经终结"的判断必须在同一个临界区内完成
      // (appendAlwaysIfUnfinished 内部经 withState),否则只是把竞争
      // 窗口缩小,而不是消除:如果先查后加,fire() 可能恰好在两次访问
      // 之间把 alwaysTasks 排空,让这次追加白追加。
      guard appendAlwaysIfUnfinished(.create(nil, .background, alwaysOperation)) else {
        // 链条已经终结:上面这个 always 任务永远不会被 fire() 排空到,
        // 也就永远不会执行。立即以当前值恢复,不再调用 catch(_:)——
        // 那会把已经注册过的 errorBlock 覆盖掉,而链条已经终结,不会再
        // 产生新的错误,调用也没有意义。
        guard resumed.claim() else { return }
        continuation.resume(returning: self.currentValue)
        return
      }

      // 链条尚未终结:可能是全新链条(本次调用是第一个终结符),也可能
      // 链条已经被别的终结符启动、正在飞行中——两种情况下追加都是正确
      // 的,fire() 迟早会走到 .finish 并排空 alwaysTasks。
      //
      // 这里走 addErrorHandler 而不是 catch(_:):后者是替换语义,会把调用方
      // 在 value() 之前登记的错误处理器整个丢掉(`p.catch { showError($0) }`
      // 之后再 `try await p.value()`,showError 就再也收不到错误了)。
      // 上面那条已终结分支拒绝调用 catch(_:) 用的正是同一条理由。
      // catch(_:) 顺带做的 beginIfNeeded() 在下面显式补上:它经同一把 isStarted
      // 门闩判断是否真的需要启动,已经在飞行中时不会二次推进链条。
      self.addErrorHandler { error in
        guard resumed.claim() else { return }
        continuation.resume(throwing: error)
      }
      self.beginIfNeeded()
    }
  }

  /// 仅在链条尚未终结时追加一个 always 任务;检查与追加在同一个临界区内
  /// 完成。返回 false 表示链条已经终结(isFinished),此时 alwaysTasks
  /// 不会再被 fire() 排空,调用方不能指望这个任务将来会被执行。
  private func appendAlwaysIfUnfinished(_ task: PromiseTask) -> Bool {
    withState {
      guard !isFinished else { return false }
      alwaysTasks.append(task)
      return true
    }
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

/// 保证 CheckedContinuation 只被恢复一次。
///
/// @unchecked Sendable 是安全的:claimed 只经由 lock 保护的临界区读写,
/// 与 Promise、ImageCachePool、SwiftyThreadPool 同一模式——线程安全靠
/// 互斥同步保证,编译器无法验证这一点,故为 unchecked。
private final class ResumeGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  /// 首次调用返回 true,之后一律返回 false。
  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !claimed else { return false }
    claimed = true
    return true
  }
}
