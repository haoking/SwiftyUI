//
//  SwiftyToast.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/17/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

@MainActor
public final class SwiftyToast {
  private lazy var toastLabel: SwiftyLabel = { [unowned self] in
    var toastLabel = SwiftyLabel(nil, .white, .init(white: 0.0, alpha: 0.7))
    toastLabel.layer.cornerRadius = 5
    toastLabel.clipsToBounds = true
    toastLabel.padding = 5.0
    toastLabel.font = .systemFont(ofSize: 12)
    return toastLabel
  }()

  /// 创建并排队显示一个 Toast。
  ///
  /// - Important: 只能在主 actor 上调用。SwiftyToast 会创建并测量 UIKit 视图、
  ///   读取当前 window scene、并修改全局的 Toast 队列,这些都要求主线程。
  ///   1.x 在后台线程调用时不会报错,但属于未定义行为(在后台创建并测量
  ///   UILabel、并发修改队列状态)。2.0 起本类型是 @MainActor 隔离的,
  ///   该约束由编译器静态强制——从非隔离上下文调用会直接编译失败。
  public init(_ text: String) {
    layoutView(text: text)
    SwiftyToastCenter.default.add(self).fire()
  }

  //    @discardableResult
  //    public class func load(_ text: String) -> SwiftyToast
  //    {
  //        return .init(text: text)
  //    }

  private func layoutView(text: String) {
    toastLabel.text = text

    let window = SwiftyGlobal.keyWindow
    let containerSize: CGSize = window?.bounds.size ?? .zero
    let isPortrait: Bool = window?.windowScene?.interfaceOrientation.isPortrait ?? true
    let constraintSize: CGSize = CGSize(
      width: containerSize.width * (280.0 / 320.0), height: CGFloat.greatestFiniteMagnitude)
    let fitSize: CGSize = toastLabel.sizeThatFits(constraintSize)

    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    if isPortrait {
      width = containerSize.width
      height = containerSize.height
      y = 30.0
    } else {
      width = containerSize.height
      height = containerSize.width
      y = 20.0
    }

    let size: CGSize = .init(width: fitSize.width + 10 + 10, height: fitSize.height + 6 + 6)
    x = (width - size.width) * 0.5
    y = height - (size.height + y)
    toastLabel.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  fileprivate func show() {
    // 异步推迟到主 actor 的下一次调度,而不是在 init 里同步挂上窗口 ——
    // 也避免无 window 时 show() -> finish() -> fire() -> show() 的同步递归。
    //
    // 这里不再走 Promise:Promise 是非隔离的调度原语,它的任务闭包是 @Sendable
    // 的(见 SwiftyPromise),在其中访问 UIKit 只能靠 MainActor.assumeIsolated
    // 做运行时桥接。show() 本就在主 actor 上,Task 会继承这份隔离,
    // 整段 UI 代码因此是静态可验证的,不需要任何运行时断言。
    Task {
      guard let window = SwiftyGlobal.keyWindow else {
        // 无可用窗口时静默丢弃,并推进队列,避免后续 toast 被永久阻塞
        SwiftyToastCenter.default.finish()
        return
      }
      self.toastLabel.alpha = 0
      window.addSubview(self.toastLabel)

      UIView.animate(
        withDuration: 0.5, delay: 0.0, options: .beginFromCurrentState,
        animations: {
          self.toastLabel.alpha = 1
        },
        completion: { _ in
          UIView.animate(
            withDuration: 2.5,
            animations: {
              self.toastLabel.alpha = 1.0001
            },
            completion: { _ in
              UIView.animate(
                withDuration: 0.5,
                animations: {
                  self.toastLabel.alpha = 0
                },
                completion: { _ in
                  self.toastLabel.removeFromSuperview()
                  SwiftyToastCenter.default.finish()
                })
            })
        })
    }
  }

  public class func cancel() {
    SwiftyToastCenter.default.cancelAll()
  }
}

// B8 已修复:queueArray 与 isFinished 仍是不加锁的普通存储属性,但本类型
// 现在是 @MainActor 隔离的,add/finish/fire 只可能在主 actor 上执行,
// 编译器保证不存在并发访问,因而无需再加锁。
@MainActor
private final class SwiftyToastCenter {
  private var queueArray: [SwiftyToast] = []
  private var isFinished: Bool = true

  public static let `default` = {
    return SwiftyToastCenter()
  }()

  private init() {}

  @discardableResult
  public func add(_ toast: SwiftyToast) -> SwiftyToastCenter {
    queueArray.append(toast)
    return self
  }

  public func finish() {
    isFinished = true
    fire()
  }

  public func fire() {
    guard let toast = queueArray.first, isFinished else { return }
    queueArray.removeFirst()
    isFinished = false
    toast.show()
  }

  public func cancelAll() {
    queueArray.removeAll()
  }
}
