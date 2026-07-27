//
//  SwiftyToast.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/17/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

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
  /// - Important: 必须在主线程调用。SwiftyToast 会创建并测量 UIKit 视图、
  ///   读取当前 window scene、并修改全局的 Toast 队列,这些都要求主线程。
  ///   1.x 在后台线程调用时不会报错,但属于未定义行为(在后台创建并测量
  ///   UILabel、并发修改队列状态)。2.0 起改为快速失败。
  ///   Task 17 给本类型加上 @MainActor 后,这一约束将由编译器强制。
  public init(_ text: String) {
    precondition(
      Thread.isMainThread,
      "SwiftyToast 必须在主线程构造:它会创建并测量 UIKit 视图、读取 window scene、"
        + "并修改全局 Toast 队列。请把这次调用移到主线程。")
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

    // SwiftyGlobal 是 @MainActor 隔离的,而本方法是非隔离的。
    // init 的 precondition 已保证我们在主线程,故此处 assumeIsolated 不会 trap。
    // Task 17 给 SwiftyToast 加上 @MainActor 后,本桥接可整体删除。
    let (containerSize, isPortrait): (CGSize, Bool) = MainActor.assumeIsolated {
      let window = SwiftyGlobal.keyWindow
      return (
        window?.bounds.size ?? .zero,
        window?.windowScene?.interfaceOrientation.isPortrait ?? true
      )
    }
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
    Promise<Void>.firstly(on: .main) {
      // SwiftyGlobal.keyWindow 是 @MainActor 隔离的;show() 本身不是——SwiftyToast
      // 的隔离标注统一推迟到 Task 17,但 Promise 保证 `on: .main` 的任务确实
      // 在主线程执行,故用 assumeIsolated 做运行时断言而非静态隔离改造。
      MainActor.assumeIsolated {
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
    }.start()
  }

  public class func cancel() {
    SwiftyToastCenter.default.cancelAll()
  }
}

// B8: queueArray 与 isFinished 是普通存储属性,没有任何同步保护。
//
// 本类型有意**不**标注 @MainActor——隔离标注统一推迟到 Task 17(原因见
// SwiftyLabel.swift"存储属性"一节的说明:本模块内显式 @MainActor 在 Swift 5
// 语言模式下会被强制执行,而 SwiftyToast(本类型的唯一调用方)同样要到
// Task 17 才统一标注,这之前提早给 SwiftyToastCenter 加锁隔离只会制造
// 桥接负担)。因此 add/finish/fire 目前仍可能被非主线程调用而与主线程读写
// queueArray/isFinished 产生竞态。
//
// Task 17 给本类型加上 @MainActor 后,add/finish/fire 天然只在主线程执行,
// 该竞态自动消除,无需额外改动——搜索本类型名即可定位。
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
