//
//  SwiftyTimer.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 9/24/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import Foundation

extension Timer {
  /// 创建一个 `interval` 秒后触发一次的 timer。
  ///
  /// 返回的 timer **尚未加入任何 RunLoop**,调用 `start()` 之后才会触发 —— 所以返回值
  /// 不可丢弃(丢掉就再也没有机会 start)。
  ///
  /// - Important: 计时从**创建**这一刻开始,不是从 `start()` 开始:创建之后隔了超过
  ///   `interval` 才 start,会立刻触发。请像 `Timer.after(1, …).start()` 这样创建后立即启动。
  public final class func after(_ interval: TimeInterval, _ wrapper: ClosureWrapper<Timer>) -> Timer
  {
    // handler 用回调参数里的 timer,不捕获返回值:捕获会形成 timer → handler → timer
    // 的环,从没 start() 过的 timer 等不到 RunLoop 的 invalidate,连同 wrapper 捕获的
    // 对象一起永久泄漏。
    return CFRunLoopTimerCreateWithHandler(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, 0, 0, 0
    ) { timer in
      wrapper.closure?(timer)
    }
  }

  /// 创建一个每 `interval` 秒触发一次的 timer。与 `after(_:_:)` 一样,需要 `start()`;
  /// 首次触发同样从创建时刻起算。
  public final class func every(_ interval: TimeInterval, _ wrapper: ClosureWrapper<Timer>) -> Timer
  {
    // 不捕获返回值,理由同 after(_:_:)。
    return CFRunLoopTimerCreateWithHandler(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0
    ) { timer in
      wrapper.closure?(timer)
    }
  }

  public final func start(
    runLoop: RunLoop = .current, modes: [RunLoop.Mode] = [RunLoop.Mode.default]
  ) {
    for mode in modes {
      runLoop.add(self, forMode: mode)
    }
  }
}
