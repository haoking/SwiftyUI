import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyTimerTests: XCTestCase {

  /// 创建后没 start() 就丢掉的 timer 不能泄漏,也不能拖着 wrapper 捕获的对象一起泄漏。
  ///
  /// handler 曾经捕获 `var timer`(返回值本身),形成 timer → handler → 捕获盒 → timer 的环。
  /// 一次性 timer 触发后 RunLoop 会 invalidate 它、放掉 handler,环因此解开;但从没
  /// start() 过的 timer 永远等不到那一刻 —— wrapper 捕获的对象(常见是 view controller)
  /// 随之永久泄漏。
  ///
  /// 判别力:让 handler 重新捕获返回值,wrapper 在作用域结束后仍然存活。
  func testUnstartedTimerDoesNotLeakItsWrapper() {
    weak var weakWrapper: ClosureWrapper<Timer>?
    autoreleasepool {
      let wrapper = ClosureWrapper<Timer> { _ in }
      weakWrapper = wrapper
      _ = Timer.after(0.01, wrapper)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    XCTAssertNil(weakWrapper, "没 start() 就丢掉的 timer 让 wrapper 泄漏了")
  }

  /// 计时从创建时刻起算(文档写明的行为):创建后等超过 interval 才 start,立刻触发。
  ///
  /// 锁住的是文档里的承诺。要改成"从 start 起算",请连同文档一起改。
  func testCountdownRunsFromCreationNotFromStart() {
    let fired = expectation(description: "fired")
    let firedAt = Box<Date?>(nil)
    let timer = Timer.after(0.3, ClosureWrapper { _ in
      firedAt.value = Date()
      fired.fulfill()
    })
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let startedAt = Date()
    timer.start()
    wait(for: [fired], timeout: 2)
    let elapsed = try! XCTUnwrap(firedAt.value).timeIntervalSince(startedAt)
    XCTAssertLessThan(elapsed, 0.15, "创建后已超过 interval,start 之后应立刻触发(实得 \(elapsed)s)")
  }

  /// start() 之后照常触发,handler 拿到的就是这个 timer。
  func testStartedTimerFiresWithItself() {
    let fired = expectation(description: "fired")
    let received = Box<Bool>(false)
    var timer: Timer?
    timer = Timer.after(0.01, ClosureWrapper { firedTimer in
      received.value = firedTimer === timer
      fired.fulfill()
    })
    timer?.start()
    wait(for: [fired], timeout: 2)
    XCTAssertTrue(received.value, "handler 应收到触发的那个 timer 本身")
  }
}
