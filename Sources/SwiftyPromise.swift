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

/// Promise 自身产生的错误(区别于任务体抛出的业务错误)。
public enum PromiseError: Error, Sendable, Equatable {
  /// 支撑该任务的 Operation 在开始执行前被取消。
  ///
  /// 最常见的来源是 `SwiftyThreadPool` 收到内存告警后调用 `removeAll()`。
  case cancelled

  /// 链条正常终结,但没有任何任务调用过 `update(...)`,因此没有值可返回。
  case noValue
}

/// 记录一个 operation 的执行块是否真的运行过。
///
/// 存在的理由:BlockOperation 的执行块不检查 isCancelled,所以取消若发生在
/// 执行**期间**,工作其实已经完成 —— 此时把链条判为取消会丢弃一个有效结果。
/// 判定条件因此是 `isCancelled && !didRun`,而不是单看 isCancelled。
///
/// Foundation 保证 completionBlock 在 operation 结束之后运行,因此在
/// completionBlock 里读到的 didRun 一定反映了执行块是否跑过。
///
/// @unchecked Sendable 的理由与 ResumeGuard 一致:唯一的可变状态只经由
/// lock 保护的临界区读写,编译器无法验证,故为 unchecked。
private final class RunFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func markRun() {
    lock.lock()
    defer { lock.unlock() }
    value = true
  }

  var didRun: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

private struct PromiseTask {
  var identifier: String?
  var perform: ThreadPerform
  var op: Operation
  /// 与本任务的 op 一一对应,由 op 的执行块置位。
  let runFlag: RunFlag
  /// 仅 value() 传入:该 always 任务被取消时用来抛错恢复 continuation。
  /// 用户经 always(_:) 追加的任务不设此项 —— 链条此时已终结,错误无处可去。
  let onCancelled: (@Sendable () -> Void)?

  private init(
    _ identifier: String? = nil, _ perform: ThreadPerform = .background, _ op: Operation,
    _ runFlag: RunFlag, _ onCancelled: (@Sendable () -> Void)?
  ) {
    self.identifier = identifier
    self.perform = perform
    self.op = op
    self.runFlag = runFlag
    self.onCancelled = onCancelled
  }

  static func create(
    _ identifier: String? = nil, _ perform: ThreadPerform = .background, _ op: Operation,
    runFlag: RunFlag, onCancelled: (@Sendable () -> Void)? = nil
  ) -> PromiseTask {
    return PromiseTask(identifier, perform, op, runFlag, onCancelled)
  }

  /// 池由调用方传入而不是直接取 SwiftyThreadPool.default:取消语义必须能在
  /// 一个与其他测试隔离的池上验证。对外的公开 API 一律仍走共享单例。
  func start(on pool: SwiftyThreadPool) {
    switch perform {
    case .main:
      OperationQueue.main.addOperation(op)
    case .background:
      pool.add(op, withIdentifier: identifier)
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

  /// 承载 `.background` 任务的线程池。
  ///
  /// internal 且默认是共享单例:公开 API 完全看不到这个参数,行为与 2.0 一致。
  /// 它存在的唯一理由是测试 —— 取消语义必须在一个与其他测试隔离的池上验证,
  /// 否则要么去挂起进程级单例(污染别的测试),要么测试根本碰不到被测的那条链。
  ///
  /// 这是一个强引用:Promise 活着,它注入的池(以及池在 init 里注册的那个
  /// 内存告警观察者)就一直活着。走公开 API 时指向的是进程级单例,本来就与
  /// 进程同寿,无所谓;注入自定义池时才有区别 —— 尤其是在 value() 文档里
  /// 记的那种"链条永远无法终结"的情形下,整条链连同这个池一起泄漏。
  internal let pool: SwiftyThreadPool

  private var tasks: [PromiseTask] = []
  private var alwaysTasks: [PromiseTask] = []
  /// 调用方经 `catch(_:)` 登记的错误处理器。替换语义,由调用方独占。
  private var errorBlock: (@Sendable (Error) -> Void)?
  /// 库内部自己的错误处理器,与 `errorBlock` **完全分开的一个槽位**。
  ///
  /// 目前唯一的使用者是 `value()`:它需要在出错时恢复自己的 continuation。
  /// 两个槽位分开,是为了让调用方的 `catch(_:)` 与库内部的 `value()` 互不干扰
  /// —— 无论两者以什么顺序被调用:
  ///
  /// - `catch(_:)` 之后 `value()`:value() 不去碰 errorBlock,调用方登记的处理器
  ///   完好无损(它曾经被 value() 内部转手调用 catch(_:) 静默覆盖掉)。
  /// - `value()` 之后 `catch(_:)`:catch(_:) 只写 errorBlock,碰不到这个槽位,
  ///   value() 的 continuation 仍然会被恢复(否则那个 await 永远挂起)。
  ///
  /// 因此 `catch(_:)` 的公开语义(替换)一个字都不用改。
  private var internalErrorHandler: (@Sendable (Error) -> Void)?
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
    let handlers: (user: (@Sendable (Error) -> Void)?, internal: (@Sendable (Error) -> Void)?) =
      withState {
        self.isError = true
        return (self.errorBlock, self.internalErrorHandler)
      }
    // 顺序有意义:先调用方的,再库内部的。内部那个(value() 的)会恢复
    // continuation,一旦恢复,await 处的代码就可能立刻继续往下跑;先跑调用方的
    // 处理器,才能保证 `await value()` 返回时它已经执行完毕,而不是留下一个
    // 由调度决定输赢的竞争。
    handlers.user?(error)
    handlers.internal?(error)
  }

  private func update(_ newValue: T?) {
    withState { self.value = newValue }
  }

  private var currentValue: T? {
    return withState { self.value }
  }

  // MARK: - 任务构建

  private func operationBuild(_ work: (@Sendable () throws -> Void)?) -> (
    op: Operation, flag: RunFlag
  ) {
    let flag = RunFlag()
    // 这里不持有 self:链条运行期间的强引用由 fire() 在投递时挂到
    // operation 的 completionBlock 上,详见 fire()
    let op = BlockOperation { [weak self] in
      // 放在块内第一句是防御性的,不是纠正性的:这里 self 其实不可能为 nil
      // (fire() 在 start(on:) 之前就把强引用 self 的 completionBlock 挂了
      // 上去,而在投递之前这个 op 只能从 self.tasks 够到),因此没有任何测试
      // 能钉住这个顺序 —— 这是预期,不是覆盖缺口。
      // 之所以仍然放在最前面:"这个块运行过"是与 self 生死无关的事实,让
      // markRun 不依赖上面那层不太显眼的可达性论证,将来谁改动 self 的持有
      // 方式也不会把它连带弄坏。一旦漏掉,completionBlock 会把跑过的块误判
      // 为取消,丢弃一份有效结果。
      flag.markRun()
      guard let self = self else { return }
      do {
        try work?()
      } catch {
        self.markError(error)
      }
    }
    return (op, flag)
  }

  private func operationBuildT(
    _ work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> (op: Operation, flag: RunFlag) {
    let flag = RunFlag()
    let op = BlockOperation { [weak self] in
      flag.markRun()
      guard let self = self else { return }
      do {
        try work(self.update, self.currentValue)
      } catch {
        self.markError(error)
      }
    }
    return (op, flag)
  }

  // MARK: - 构造

  // init 期间还没有第二个线程能看到 self,直接写 tasks 是安全的
  private init(
    pool: SwiftyThreadPool, _ identifier: String? = nil,
    _ perform: ThreadPerform = .background, _ work: (@Sendable () throws -> Void)?
  ) {
    self.pool = pool
    let built = operationBuild(work)
    tasks.append(.create(identifier, perform, built.op, runFlag: built.flag))
  }

  private init(
    pool: SwiftyThreadPool, _ identifier: String? = nil,
    _ perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) {
    self.pool = pool
    let built = operationBuildT(work)
    tasks.append(.create(identifier, perform, built.op, runFlag: built.flag))
  }

  @discardableResult
  public class func firstly(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
  ) -> Promise {
    return Promise(pool: .default, identifier, perform, work)
  }

  @discardableResult
  public class func firstly(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    return Promise(pool: .default, identifier, perform, work: work)
  }

  /// 供测试注入一个隔离的线程池。不是公开 API。
  @discardableResult
  internal class func firstly(
    pool: SwiftyThreadPool, with identifier: String? = nil,
    on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
  ) -> Promise {
    return Promise(pool: pool, identifier, perform, work)
  }

  /// 供测试注入一个隔离的线程池。不是公开 API。
  @discardableResult
  internal class func firstly(
    pool: SwiftyThreadPool, with identifier: String? = nil,
    on perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    return Promise(pool: pool, identifier, perform, work: work)
  }

  // MARK: - 链式

  @discardableResult
  public func then(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
  ) -> Promise {
    let built = operationBuild(work)
    withState { tasks.append(.create(identifier, perform, built.op, runFlag: built.flag)) }
    return self
  }

  @discardableResult
  public func then(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    work: @escaping @Sendable (_ update: (T?) -> Void, _ value: T?) throws -> Void
  ) -> Promise {
    let built = operationBuildT(work)
    withState { tasks.append(.create(identifier, perform, built.op, runFlag: built.flag)) }
    return self
  }

  @discardableResult
  public func always(
    with identifier: String? = nil, on perform: ThreadPerform = .background,
    _ work: (@Sendable () throws -> Void)?
  ) -> Promise {
    // always 的 operation 不参与 fire() 链条,完成后无需推进;
    // 此时链条已终结,再抛错也无处可去,直接吞掉
    let flag = RunFlag()
    let operation = BlockOperation {
      flag.markRun()
      _ = try? work?()
    }
    withState { alwaysTasks.append(.create(identifier, perform, operation, runFlag: flag)) }
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
  ///   重复调用后者覆盖前者,传 nil 则清空。这条语义是公开契约,不要改动。
  ///   它只写 `errorBlock` 这一个槽位,库内部的处理器在
  ///   `internalErrorHandler` 里,两者互不影响;因此 `catch(_:)` 与 `value()`
  ///   无论谁先谁后,都不会破坏对方(见 internalErrorHandler 的说明)。
  public func `catch`(_ errorBlock: (@Sendable (Error) -> Void)? = nil) {
    withState { self.errorBlock = errorBlock }
    beginIfNeeded()
  }

  /// 往库内部那个槽位上加挂一个错误处理器。绝不触碰调用方的 `errorBlock`。
  ///
  /// 内部槽位自己是**追加**语义:同一个 Promise 上可能有多个并发的 `value()`
  /// 调用,各自持有一个只能恢复一次的 continuation。若这里写成替换,后一次
  /// 调用会把前一次的处理器顶掉,前一个 await 就永远挂在那里了。
  ///
  /// 读旧值与写组合值必须在同一个临界区内完成:先读后写会让两个并发的追加
  /// 互相覆盖,只是把竞争窗口缩小而不是消除 —— 与 appendAlwaysIfUnfinished
  /// 同一条理由。
  private func addInternalErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) {
    withState {
      guard let existing = self.internalErrorHandler else {
        self.internalErrorHandler = handler
        return
      }
      self.internalErrorHandler = { error in
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

      let flag = RunFlag()
      let alwaysOperation = BlockOperation {
        flag.markRun()
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
      guard appendAlwaysIfUnfinished(.create(nil, .background, alwaysOperation, runFlag: flag))
      else {
        // 链条已经终结:上面这个 always 任务永远不会被 fire() 排空到,
        // 也就永远不会执行。立即以当前值恢复,也不必登记任何错误处理器 ——
        // 链条已经终结,不会再产生新的错误。
        guard resumed.claim() else { return }
        continuation.resume(returning: self.currentValue)
        return
      }

      // 链条尚未终结:可能是全新链条(本次调用是第一个终结符),也可能
      // 链条已经被别的终结符启动、正在飞行中——两种情况下追加都是正确
      // 的,fire() 迟早会走到 .finish 并排空 alwaysTasks。
      //
      // 登记在**库内部那个槽位**上,而不是调用方的 errorBlock 上。
      // 这样两个方向都成立,与 catch(_:) 的调用顺序无关:
      //   catch 在前 —— 调用方登记的处理器不会被这里覆盖;
      //   catch 在后 —— catch(_:) 只写 errorBlock,覆盖不掉下面这个处理器,
      //                 这个 await 因此不会被别人的一句 catch 挂死。
      // 曾经这里是 `self.catch { ... }`,两个方向都会坏掉一个。
      //
      // beginIfNeeded() 显式补上(以前由 catch(_:) 顺带完成):它经同一把
      // isStarted 门闩判断是否真的需要启动,已经在飞行中时不会二次推进链条。
      self.addInternalErrorHandler { error in
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
      // Promise 时链条也能跑完。
      //
      // 它确实构成一个环,但是瞬态的:self → pool → queue → op →
      // completionBlock → self。之所以不泄漏,理由与下面这句原本就写着的一样
      // ——task 在上面的临界区里已被移出 tasks,operation 完成后由队列释放,
      // 环随之断开。(2.0 时 pool 还是直接取的单例,self 够不到 op,那时确实
      // 连环都不成环;注入 pool 之后这条边才出现,结论不变,写清楚免得误导。)
      //
      // 只捕获 flag,**不要**捕获 task:task 持有 op,把它捕进 op 自己的
      // completionBlock 会造成 op → completionBlock → task → op 的环 ——
      // 正是下面 [weak op] 想避免的东西。RunFlag 不引用 op,捕获它是安全的。
      let flag = task.runFlag
      task.op.completionBlock = { [weak op = task.op] in
        // isCancelled 单独成立不够:取消若发生在执行期间,工作其实已完成,
        // 此时判为取消会丢弃一个有效结果(见 RunFlag 的说明)。
        if op?.isCancelled == true && !flag.didRun {
          // markError 置 isError,紧接着的 fire() 会走 isError 分支丢弃剩余
          // 任务并终结 —— 复用既有的错误终结路径,不新增状态。
          self.markError(PromiseError.cancelled)
        }
        self.fire()
      }
      task.start(on: pool)
    case .finish(let pending):
      // always 在链条终结之后才执行(B11)
      for task in pending {
        // 与 .run 分支同理:只捕获 flag 与 onCancelled,不捕获 task。
        //
        // 这个 completionBlock 是 2.1 新加的。2.0 里 always 任务是"投递完就
        // 不管"的,一旦被取消就彻底静默 —— 而 value() 恰恰把恢复 continuation
        // 的逻辑放在一个 always 任务里,于是 await 永远挂在那里(见 Task 3)。
        let flag = task.runFlag
        let onCancelled = task.onCancelled
        task.op.completionBlock = { [weak op = task.op] in
          if op?.isCancelled == true && !flag.didRun {
            // 用户经 always(_:) 追加的任务没有 onCancelled —— 链条已终结,
            // 错误无处可去。只有 value() 会传,用来抛错恢复它的 continuation。
            onCancelled?()
          }
        }
        task.start(on: pool)
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
