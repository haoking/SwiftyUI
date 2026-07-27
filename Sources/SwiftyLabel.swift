//
//  SwiftyLabel.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/26/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

/// 用 TextKit 自绘文本的轻量标签。
///
/// 继承 UIView 而非 UILabel,绘制路径更短。全部属性为真实存储属性,
/// 读取不经过 objc runtime(1.x 用 associated object,每帧每个 label
/// 至少 4 次哈希查找)。
public class SwiftyLabel: UIView, TextEditable {

  // MARK: - TextKit

  private let container = NSTextContainer()
  private let layoutManager = NSLayoutManager()

  // MARK: - 存储属性
  //
  // 下面各 setter 中的 `if Thread.isMainThread { setNeedsDisplay() }` 是**临时**写法,
  // 沿用自 1.x —— 当时这些属性可能从任意线程被设置。
  //
  // 本类型有意**不**标注 @MainActor:在 Swift 5 语言模式下,本模块内显式标注的
  // @MainActor 会被强制执行,而 SwiftyButton 持有一个 SwiftyLabel 作为 titleLabel
  // 并在其非隔离的 init 中访问它,此时标注会立即导致编译失败。
  //
  // Task 17 会为全部 UI 类型统一加上 @MainActor,届时这些守卫应当**一并删除**,
  // 直接调用 setNeedsDisplay()。搜索 `Thread.isMainThread` 可定位全部 10 处。

  public var usesIntrinsicContentSize: Bool = true {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  public var textAlignment: TextContentAlignment = .center {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  public var font: UIFont = .systemFont(ofSize: UIFont.systemFontSize) {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  /// 2.0 起为非可选。1.x 声明为 UIColor? 但 getter 永不返回 nil,
  /// 且合成属性字符串时对它强解包。
  public var textColor: UIColor = .black {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  public var paragraphStyle: NSParagraphStyle = .default {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  public var shadow: NSShadow? = nil {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  public var attributedText: NSAttributedString? = nil {
    didSet {
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  // MARK: - 经由 NSTextContainer 的属性

  /// 默认 0,表示不限行数。
  public var numberOfLines: Int {
    get { container.maximumNumberOfLines }
    set {
      container.maximumNumberOfLines = newValue
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  /// NSTextContainer 的 lineFragmentPadding。默认 0。
  public var padding: CGFloat {
    get { container.lineFragmentPadding }
    set {
      container.lineFragmentPadding = newValue
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  /// 默认 byTruncatingTail。
  public var lineBreakMode: NSLineBreakMode {
    get { container.lineBreakMode }
    set {
      container.lineBreakMode = newValue
      if Thread.isMainThread { setNeedsDisplay() }
    }
  }

  /// 纯文本。读取时返回 attributedText 的字符串内容。
  public var text: String? {
    get { attributedText?.string }
    set {
      if let newValue = newValue {
        attributedText = NSAttributedString(string: newValue)
      } else {
        attributedText = nil
      }
    }
  }

  // MARK: - 构造

  public init(_ text: String? = nil, _ textColor: UIColor? = nil, _ backgroundColor: UIColor? = nil)
  {
    super.init(frame: .zero)

    layoutManager.addTextContainer(container)

    container.maximumNumberOfLines = 0
    container.lineFragmentPadding = 0
    container.lineBreakMode = .byTruncatingTail

    isHidden = false
    alpha = 1.0
    contentMode = .redraw
    isUserInteractionEnabled = false

    self.text = text
    if let textColor = textColor { self.textColor = textColor }
    self.backgroundColor = backgroundColor
  }

  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - 绘制

  /// internal(而非 private):`draw`/`intrinsicContentSize`/`sizeThatFits` 用它渲染,
  /// 测试也靠 `@testable import` 读它来验证「显式属性不被覆盖」——因为它是一份从
  /// `attributedText` 拷贝出的可变副本,merge 的效果不会写回 `attributedText` 本身。
  var mergedAttributedText: NSAttributedString? {
    guard let attributedText = attributedText else { return nil }
    let result = NSMutableAttributedString(attributedString: attributedText)
    result.fillMissingAttribute(.font, value: font)
    result.fillMissingAttribute(.foregroundColor, value: textColor)
    result.fillMissingAttribute(.paragraphStyle, value: paragraphStyle)
    if let shadow = shadow {
      result.fillMissingAttribute(.shadow, value: shadow)
    }
    return result
  }

  open override func draw(_ rect: CGRect) {
    guard let attributedText = mergedAttributedText else { return }

    let storage = NSTextStorage(attributedString: attributedText)
    storage.addLayoutManager(layoutManager)

    container.size = rect.size
    let used = layoutManager.usedRect(for: container)
    let origin = textAlignment.alignOffset(
      viewSize: rect.size,
      containerSize: used.integral.size)

    let glyphRange = layoutManager.glyphRange(for: container)
    layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
  }

  open override var intrinsicContentSize: CGSize {
    guard usesIntrinsicContentSize else { return bounds.size }
    guard let attributedText = mergedAttributedText else { return .zero }

    let constraint = CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
    return attributedText.boundingRect(
      with: constraint,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    ).integral.size
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    guard let attributedText = mergedAttributedText else { return .zero }

    let storage = NSTextStorage(attributedString: attributedText)
    storage.addLayoutManager(layoutManager)

    container.size = size
    return layoutManager.usedRect(for: container).integral.size
  }

  open override func sizeToFit() {
    super.sizeToFit()
    frame.size = sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
  }
}

extension NSMutableAttributedString {
  /// 只在该属性尚未设置的区间填入默认值,不覆盖调用方通过
  /// attributedText 显式指定的属性。
  fileprivate func fillMissingAttribute(_ name: NSAttributedString.Key, value: Any) {
    let full = NSRange(location: 0, length: length)
    enumerateAttribute(name, in: full, options: .reverse) { existing, range, _ in
      if existing == nil {
        addAttributes([name: value], range: range)
      }
    }
  }
}
