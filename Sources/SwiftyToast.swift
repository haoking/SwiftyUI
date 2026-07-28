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
  /// Toast 视图的 accessibilityIdentifier。
  ///
  /// 与 SwiftyAlertView 给自己的根视图设 `"SwiftyAlert"` 是同一件事、同一个用途:
  /// 让这个直接挂在 window 上、不属于任何 view controller 的视图可以被外部识别。
  ///
  /// **必须显式 nonisolated**:SwiftyToast 是 @MainActor 隔离的类型,
  /// 类型成员默认继承这份隔离,`public static let` 也不例外。而这个常量存在的
  /// 全部意义就是给 UI 自动化与外部工具用,那类代码通常是非隔离的 ——
  /// 继承隔离会让它在自己唯一的目标场景里根本引用不了:
  ///
  ///     error: main actor-isolated class property 'accessibilityIdentifier'
  ///     can not be referenced from a nonisolated context
  ///
  /// 一个不可变的 String 常量本来也没有任何需要主 actor 保护的可变状态。
  public nonisolated static let accessibilityIdentifier: String = "SwiftyToast"

  private lazy var toastLabel: SwiftyLabel = { [unowned self] in
    var toastLabel = SwiftyLabel(nil, .white, .init(white: 0.0, alpha: 0.7))
    toastLabel.layer.cornerRadius = 5
    toastLabel.clipsToBounds = true
    toastLabel.padding = 5.0
    toastLabel.font = .systemFont(ofSize: 12)
    // SwiftyLabel 是 UIView 子类、文本由 TextKit 自绘,不像 UILabel 那样自带
    // 无障碍暴露 —— 不设这几项,toast 对 VoiceOver 完全是一块沉默的色块。
    toastLabel.isAccessibilityElement = true
    toastLabel.accessibilityTraits = .staticText
    toastLabel.accessibilityIdentifier = Self.accessibilityIdentifier
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
    toastLabel.accessibilityLabel = text

    let window = SwiftyGlobal.keyWindow
    let containerSize: CGSize = window?.bounds.size ?? .zero
    let isPortrait: Bool = window?.windowScene?.interfaceOrientation.isPortrait ?? true
    let constraintSize: CGSize = CGSize(
      width: containerSize.width * (280.0 / 320.0), height: CGFloat.greatestFiniteMagnitude)
    let fitSize: CGSize = toastLabel.sizeThatFits(constraintSize)

    // B22:横屏下原本把 containerSize 的宽高**对调**再用
    // (width = containerSize.height、height = containerSize.width)。
    // 那是 iOS 7 及更早的写法——那时 window 不跟着界面旋转,bounds 恒为竖屏尺寸,
    // 所以横屏要手工换算。iOS 8 起 window.bounds 本身就是旋转后的尺寸,再对调一次
    // 等于把结果转回竖屏坐标:实测 402×874 的设备转到横屏(窗口 874×402)后,
    // toast 被放到 (132.5, 827) —— y 比窗口高度还大 400 多点,整块**在屏幕外**,
    // 用户什么也看不到。与 B17(缓存屏幕尺寸)、SwiftyAlertView 弃用 UIScreen.main
    // 属于同一类缺陷:对"屏幕/窗口几何"做了一个早已不成立的静态假设。
    // 现在直接用 containerSize,只保留两种朝向下不同的底部留白。
    let bottomMargin: CGFloat = isPortrait ? 30.0 : 20.0
    let size: CGSize = .init(width: fitSize.width + 10 + 10, height: fitSize.height + 6 + 6)
    let x: CGFloat = (containerSize.width - size.width) * 0.5
    let y: CGFloat = containerSize.height - (size.height + bottomMargin)
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
