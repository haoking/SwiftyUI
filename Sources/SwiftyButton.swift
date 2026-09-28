//
//  SwiftyButton.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 9/22/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

@MainActor
public class SwiftyButton: UIControl, ImageSettable {
  public lazy var titleLabel: SwiftyLabel = { [unowned self] in
    let titleLabel = SwiftyLabel(nil, .black, .clear)
    titleLabel.addTo(self)
    titleLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    return titleLabel
  }()

  public var backgroundImage: UIImage? {
    didSet { applyBackgroundImage(backgroundImage) }
  }

  /// 防重复点击的忽略窗口,单位秒。设为 0 可关闭。
  /// 1.x 硬编码为 1.0 且不可配置。
  public var ignoreEventInterval: TimeInterval = 1.0

  /// 点击回调。1.x 用 associated object 保存,2.0 起为真实存储属性。
  private var tapHandler: ClosureWrapper<SwiftyButton>?

  /// 处于忽略窗口内。
  private var isIgnoringEvent: Bool = false

  public init(
    _ title: String? = nil, _ image: UIImage? = nil, _ handler: ClosureWrapper<SwiftyButton>
  ) {
    super.init(frame: .zero)
    backgroundColor = .clear
    isMultipleTouchEnabled = false
    isHidden = false
    alpha = 1.0

    titleLabel.text = title
    // Swift 的属性观察器对"在本类自身的初始化器中直接赋值自有存储属性"不触发,
    // 因此下面这行不会执行 backgroundImage 的 didSet,layer.contents 也就永远不会
    // 被设置 —— 按钮会渲染成空白方块。必须显式调用一次。
    //
    // 对照:SwiftyImageView 经 image 计算属性间接赋值,其观察器会触发;
    // SwiftyView 覆写的是超类属性,同样会触发。只有本类是直接赋值。
    backgroundImage = image
    applyBackgroundImage(image)
    tapHandler = handler
    addTarget(self, action: #selector(btnTapped(_:)), for: .touchUpInside)
    // 继承 UIControl、标题自绘,不像 UIButton 那样自带无障碍暴露:默认按按钮暴露,
    // label 取当前标题(见 accessibilityLabel)。
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  /// 未显式设置时取当前标题。
  public override var accessibilityLabel: String? {
    get { super.accessibilityLabel ?? titleLabel.text }
    set { super.accessibilityLabel = newValue }
  }

  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // btnTapped 从 @objc private 放宽为 internal,作为测试接缝:这个 SPM 测试
  // target 没有宿主 App,UIControl.sendActions(for:) 的默认实现依赖
  // UIApplication.shared 做实际分发,在该环境下是彻底的 no-op(实测确认:
  // target/action 注册本身没问题,分发这一步没有发生),因此测试需要直接
  // 调用 btnTapped 而不能走 sendActions。
  //
  // 注意这与 Task 13(docs/superpowers/plans/2026-07-27-swiftyui-2.0-modernization.md)
  // 把 mergedAttributedText 改为 internal **不是同一类变更**——
  // 那个属性此前是 public,Task 13 是收紧;这里是从 private 放宽。
  // 之所以可接受:@objc 方法本就通过 ObjC 运行时对外可达,
  // Swift 访问级别并不构成真正的封装边界。
  @objc
  func btnTapped(_ sender: SwiftyButton) {
    // 1.x 靠 swizzle UIControl.sendAction 实现防抖。改为在此处直接判断,
    // 既不需要改写运行时,也让间隔变得可配置。
    guard !isIgnoringEvent else { return }

    if ignoreEventInterval > 0 {
      isIgnoringEvent = true
      DispatchQueue.main.asyncAfter(deadline: .now() + ignoreEventInterval) { [weak self] in
        self?.isIgnoringEvent = false
      }
    }

    tapHandler?.closure?(sender)
  }
}
