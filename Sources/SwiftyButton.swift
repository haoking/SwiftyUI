//
//  SwiftyButton.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/22/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

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
    backgroundImage = image
    tapHandler = handler
    addTarget(self, action: #selector(btnTapped(_:)), for: .touchUpInside)
  }

  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // internal(而非 private):单元测试通过 `@testable import` 直接调用本方法
  // 来模拟点击并验证防抖逻辑。原因:这个 SPM 测试 target 没有宿主 App,
  // UIControl.sendActions(for:) 的默认实现依赖 UIApplication.shared 做实际
  // 分发,在该环境下是彻底的 no-op(实测确认:target/action 注册本身没问题,
  // 分发这一步没有发生),因此测试改为直接调用 btnTapped。与 Task 13 把
  // mergedAttributedText 从 private 改 internal 的理由一致。
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
