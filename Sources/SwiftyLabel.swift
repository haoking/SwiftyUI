//
//  SwiftyLabel.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 9/26/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import UIKit

/// 用 TextKit 自绘文本的轻量标签。
///
/// 继承 UIView 而非 UILabel,绘制路径更短。全部属性为真实存储属性,
/// 读取不经过 objc runtime(1.x 用 associated object,每帧每个 label
/// 至少 4 次哈希查找)。
@MainActor
public class SwiftyLabel: UIView, TextEditable {

  // MARK: - TextKit

  private let container = NSTextContainer()
  private let layoutManager = NSLayoutManager()
  /// 常驻的文本存储,init 里挂上 layoutManager 后一直用这一份。
  ///
  /// 2.x 每次 draw、每次 sizeThatFits(intrinsicContentSize 也走这里,Auto Layout
  /// 一轮布局会问好几次)都拷贝一份 attributedText、补齐默认属性、新建 NSTextStorage
  /// 再挂上 layoutManager,字形每次都从头生成。现在只在影响合并结果的属性变了之后
  /// 才重建一次;容器尺寸变化只让布局失效,字形照旧复用。
  private let textStorage = NSTextStorage()
  /// mergedAttributedText 依赖的属性变过、还没同步进 textStorage。
  private var textStorageIsStale = true

  // MARK: - 存储属性
  //
  // 各 setter 直接调用 setNeedsDisplay():本类型是 @MainActor 隔离的,
  // 编译器已保证赋值只可能发生在主 actor 上。
  // (1.x 允许从任意线程赋值,2.0 早期版本因此在每个 setter 里加了
  // `if Thread.isMainThread` 守卫;隔离生效后这些守卫恒为真,已全部删除。)
  //
  // 会改变排版尺寸的属性走 textLayoutDidChange(),额外让 intrinsicContentSize
  // 失效 —— 否则 Auto Layout 不会再来询问,改了文本高度也不变。

  public var usesIntrinsicContentSize: Bool = true {
    didSet { textLayoutDidChange() }
  }

  public var textAlignment: TextContentAlignment = .center {
    didSet { setNeedsDisplay() }
  }

  public var font: UIFont = .systemFont(ofSize: UIFont.systemFontSize) {
    didSet {
      textStorageIsStale = true
      textLayoutDidChange()
    }
  }

  /// 2.0 起为非可选。1.x 声明为 UIColor? 但 getter 永不返回 nil,
  /// 且合成属性字符串时对它强解包。
  public var textColor: UIColor = .black {
    didSet {
      textStorageIsStale = true
      setNeedsDisplay()
    }
  }

  // 下面三个属性赋值时拷贝(@NSCopying),与 UILabel 的 attributedText 是 copy 属性同一语义:
  // 文本存储是缓存的(见 textStorage),调用方事后就地修改自己赋进来的可变对象,缓存无从
  // 知晓。拷贝之后,改原对象对 label 没有影响,要生效就重新赋值。
  @NSCopying public var paragraphStyle: NSParagraphStyle = .default {
    didSet {
      textStorageIsStale = true
      textLayoutDidChange()
    }
  }

  @NSCopying public var shadow: NSShadow? = nil {
    didSet {
      textStorageIsStale = true
      setNeedsDisplay()
    }
  }

  @NSCopying public var attributedText: NSAttributedString? = nil {
    didSet {
      textStorageIsStale = true
      textLayoutDidChange()
    }
  }

  // MARK: - 经由 NSTextContainer 的属性

  /// 默认 0,表示不限行数。
  public var numberOfLines: Int {
    get { container.maximumNumberOfLines }
    set {
      container.maximumNumberOfLines = newValue
      containerDidChange()
    }
  }

  /// NSTextContainer 的 lineFragmentPadding。默认 0。
  public var padding: CGFloat {
    get { container.lineFragmentPadding }
    set {
      container.lineFragmentPadding = newValue
      containerDidChange()
    }
  }

  /// 默认 byTruncatingTail。
  public var lineBreakMode: NSLineBreakMode {
    get { container.lineBreakMode }
    set {
      container.lineBreakMode = newValue
      containerDidChange()
    }
  }

  private func textLayoutDidChange() {
    setNeedsDisplay()
    invalidateIntrinsicContentSize()
  }

  /// 行数、padding、换行方式只存在于文本容器上:改了它们,文本存储不用重建,
  /// 但 layoutManager 手里那份按旧设置排好的布局必须作废。
  ///
  /// 实测 NSTextContainer 的这几个 setter 自己就会让布局失效:去掉下面
  /// textContainerChangedGeometry 这一行,testCachedLayoutMatchesFreshLabelAfterMutations
  /// 照样通过。保留它是防御性的 —— 那是 TextKit 的实现行为,文档没有承诺;
  /// 显式失效的代价只是把已失效的布局再标记一次。
  private func containerDidChange() {
    layoutManager.textContainerChangedGeometry(container)
    textLayoutDidChange()
  }

  // MARK: - 无障碍

  /// 未显式设置时取当前文本。
  public override var accessibilityLabel: String? {
    get { super.accessibilityLabel ?? attributedText?.string }
    set { super.accessibilityLabel = newValue }
  }

  // MARK: - isOpaque
  //
  // 与 SwiftyView 同一写法:背景色或 alpha 变了就重算 isOpaque。本类型自绘文本,
  // backing store 是否不透明取决于它;UIView 默认 true,而 Apple 要求透明视图设为 false。
  // 1.x 靠首次 addTo 触发的全局 swizzle 顺带维护,2.0 把 swizzle 改成可选开启(B15)
  // 之后,这里就没人管了。

  public override var backgroundColor: UIColor? {
    didSet { updateOpaque() }
  }

  public override var alpha: CGFloat {
    didSet { updateOpaque() }
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
    textStorage.addLayoutManager(layoutManager)

    container.maximumNumberOfLines = 0
    container.lineFragmentPadding = 0
    container.lineBreakMode = .byTruncatingTail

    isHidden = false
    alpha = 1.0
    contentMode = .redraw
    isUserInteractionEnabled = false
    // 文本由 TextKit 自绘,不像 UILabel 那样自带无障碍暴露:默认按静态文本暴露,
    // label 取当前文本(见 accessibilityLabel)。
    isAccessibilityElement = true
    accessibilityTraits = .staticText

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

  /// 只在相关属性变过之后,才把合并好的属性串同步进常驻的 textStorage。
  private func syncTextStorageIfNeeded() {
    guard textStorageIsStale else { return }
    textStorageIsStale = false
    textStorage.setAttributedString(mergedAttributedText ?? NSAttributedString())
  }

  open override func draw(_ rect: CGRect) {
    guard attributedText != nil else { return }
    syncTextStorageIfNeeded()

    // 排版与对齐一律按 bounds,不按 rect:rect 是 UIKit 传来的脏矩形,局部重绘
    // (setNeedsDisplay(_:))时它只是 bounds 的一块,拿它当容器会把整段文本重排进去。
    // 超出脏矩形的部分由 UIKit 的裁剪丢掉。
    container.size = bounds.size
    let used = layoutManager.usedRect(for: container)
    let origin = textAlignment.alignOffset(
      viewSize: bounds.size,
      containerSize: used.integral.size)

    let glyphRange = layoutManager.glyphRange(for: container)
    layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
  }

  open override var intrinsicContentSize: CGSize {
    guard usesIntrinsicContentSize else { return bounds.size }
    // 与 draw / sizeThatFits 走同一条 TextKit 路径:numberOfLines、padding、lineBreakMode
    // 都只存在于文本容器上。曾经这里用 boundingRect 另算一遍,numberOfLines = 1 时
    // 也给出多行高度,padding 也不计入。
    // 换行宽度取当前 bounds 宽;还没布局过(宽为 0)时按不限宽量。
    let width = bounds.width > 0 ? bounds.width : CGFloat.greatestFiniteMagnitude
    return sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    guard attributedText != nil else { return .zero }
    syncTextStorageIfNeeded()

    container.size = size
    return layoutManager.usedRect(for: container).integral.size
  }

  open override func sizeToFit() {
    // 不调 super:UIView 的默认实现只是按 bounds 量一次再设尺寸,这里整个取代它。
    // 换行宽度取当前 bounds 宽;还没布局过(宽为 0)时按不限宽量,与 intrinsicContentSize 一致。
    let width = bounds.width > 0 ? bounds.width : CGFloat.greatestFiniteMagnitude
    frame.size = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
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
