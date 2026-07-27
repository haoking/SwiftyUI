//
//  SwiftyView.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/26/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

/// 轻量视图基类:自动维护 isOpaque,减少离屏混合。
///
/// SwiftyView 与本文件中的 UIView 扩展有意不标注 @MainActor —— 原因见
/// SwiftyLabel.swift 中"存储属性"一节的说明,Task 17 会统一为全部 UI 类型
/// 加上隔离标注。
public class SwiftyView: UIView {
  public init() {
    super.init(frame: .zero)
    isHidden = false
    alpha = 1.0
    backgroundColor = .clear
  }

  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // 用属性观察替代 1.x 对整个 App 所有 UIView 的 swizzle(B15)。
  public override var backgroundColor: UIColor? {
    didSet { updateOpaque() }
  }

  public override var alpha: CGFloat {
    didSet { updateOpaque() }
  }
}

extension UIView {
  /// 添加到父视图并返回自身,便于链式调用。
  ///
  /// 1.x 在这里惰性触发全局 swizzle,导致 App 行为取决于是否调用过本方法。
  /// 2.0 起本方法无副作用(B15)。
  @discardableResult
  public final func addTo(_ view: UIView) -> Self {
    view.addSubview(self)
    return self
  }

  /// 根据背景色与 alpha 重算 isOpaque。
  ///
  /// 完全不透明的视图可以让合成器跳过混合。保持 public 且留在本扩展中:
  /// ImageSettable.applyBackgroundImage(_:) 依赖它。
  public final func updateOpaque() {
    if let color = backgroundColor, color.alphaValue == 1.0, alpha == 1.0 {
      isOpaque = true
    } else {
      isOpaque = false
    }
  }
}

/// 库级配置入口。
@MainActor
public enum SwiftyUI {
  private static var didEnableGlobalOpaqueOptimization = false

  /// 为宿主 App 中**所有** UIView 自动维护 isOpaque。
  ///
  /// 实现方式是 swizzle UIView 的 backgroundColor 与 alpha setter,
  /// 因此会影响整个 App,包括你没有使用 SwiftyUI 的部分。
  /// 默认不启用;需要这项收益的调用方显式开启并自行承担风险。
  ///
  /// 重复调用无效果。必须在主线程调用。
  public static func enableGlobalOpaqueOptimization() {
    guard !didEnableGlobalOpaqueOptimization else { return }
    didEnableGlobalOpaqueOptimization = true

    UIView.swizzleInstance(
      #selector(setter: UIView.backgroundColor),
      #selector(UIView.swiftyui_setBackgroundColor(_:)))
    UIView.swizzleInstance(
      #selector(setter: UIView.alpha),
      #selector(UIView.swiftyui_setAlpha(_:)))
  }
}

extension UIView {
  @objc
  fileprivate func swiftyui_setBackgroundColor(_ color: UIColor?) {
    swiftyui_setBackgroundColor(color)  // swizzle 后指向原实现
    updateOpaque()
  }

  @objc
  fileprivate func swiftyui_setAlpha(_ alpha: CGFloat) {
    swiftyui_setAlpha(alpha)
    updateOpaque()
  }
}
