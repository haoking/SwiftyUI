import UIKit
import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyLabelTests: XCTestCase {

  func testInitAppliesTextAndColors() {
    let label = SwiftyLabel("hello", .white, .blue)
    XCTAssertEqual(label.text, "hello")
    XCTAssertEqual(label.textColor, .white)
    XCTAssertEqual(label.backgroundColor, .blue)
  }

  func testDefaultsMatchDocumentedValues() {
    let label = SwiftyLabel()
    XCTAssertNil(label.text)
    XCTAssertEqual(label.textColor, .black)
    XCTAssertEqual(label.textAlignment, .center)
    XCTAssertEqual(label.numberOfLines, 0)
    XCTAssertEqual(label.padding, 0)
    XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
    XCTAssertTrue(label.usesIntrinsicContentSize)
    XCTAssertFalse(label.isUserInteractionEnabled)
  }

  /// SwiftyLabel 自绘文本,backing store 是否不透明取决于 isOpaque,必须随背景色与 alpha 维护。
  ///
  /// UIView 的 isOpaque 默认是 true。Apple 的约定:视图完全或部分透明时必须设为 false,
  /// 否则"结果不可预期"。SwiftyLabel 曾经从不维护它 —— 1.x 靠首次 addTo 触发的全局
  /// swizzle 顺带维护,2.0 把 swizzle 改成可选开启之后就没人管了,透明、半透明背景的
  /// label(toast 的 0.7 黑、SwiftyButton 标题的 .clear)都顶着 isOpaque = true。
  ///
  /// 判别力:删掉 SwiftyLabel 对 backgroundColor / alpha 的覆写,前两条断言失败。
  func testOpaqueTracksBackgroundColorAndAlpha() {
    XCTAssertFalse(SwiftyLabel("x", .red, .clear).isOpaque, "透明背景不能声称不透明")
    XCTAssertFalse(SwiftyLabel("x").isOpaque, "没有背景色时不能声称不透明")

    let label = SwiftyLabel("x", .red, .white)
    XCTAssertTrue(label.isOpaque, "不透明背景、alpha 为 1 时应为不透明")
    label.alpha = 0.5
    XCTAssertFalse(label.isOpaque, "alpha 小于 1 时应为不透明 false")
  }

  /// SwiftyLabel 默认是 staticText 无障碍元素,label 取文本;显式设置优先。
  ///
  /// 文本由 TextKit 自绘,不像 UILabel 那样自带无障碍暴露。曾经什么都不设,
  /// VoiceOver 读不到;SwiftyToast 与示例 App 只能各自在调用点手工补。
  ///
  /// 判别力:删掉 init 里的两项默认值与 accessibilityLabel 覆写,前三条断言失败。
  func testExposesTextToAccessibility() {
    let label = SwiftyLabel("Hello")
    XCTAssertTrue(label.isAccessibilityElement)
    XCTAssertTrue(label.accessibilityTraits.contains(.staticText))
    XCTAssertEqual(label.accessibilityLabel, "Hello")

    label.text = "World"
    XCTAssertEqual(label.accessibilityLabel, "World", "label 应跟随当前文本")

    label.accessibilityLabel = "自定义"
    XCTAssertEqual(label.accessibilityLabel, "自定义", "显式设置的 label 优先")
  }

  func testTextRoundTripsThroughAttributedText() {
    let label = SwiftyLabel()
    label.text = "abc"
    XCTAssertEqual(label.attributedText?.string, "abc")
    label.text = nil
    XCTAssertNil(label.attributedText)
  }

  func testSizeThatFitsGrowsWithText() {
    let label = SwiftyLabel("x")
    let short = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
    label.text = "a much longer piece of text that should wrap"
    let long = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
    XCTAssertGreaterThan(long.height, short.height)
  }

  /// Auto Layout 下改文本,label 的高度要跟着变。
  ///
  /// UIKit 的契约:影响 intrinsicContentSize 的状态变化后,视图必须调用
  /// `invalidateIntrinsicContentSize()`,否则布局引擎不会再来询问。各 setter 曾经
  /// 只调 setNeedsDisplay(),于是文本变长以后 label 仍停在旧高度,多出来的行被裁掉。
  ///
  /// 宽度用约束钉死,只让高度走 intrinsicContentSize:这样测的正是"有没有失效",
  /// 不掺进 intrinsicContentSize 以当前 bounds 宽度为换行宽度的那层自指。
  ///
  /// 容器必须挂在 window 上:失效之后由 window 驱动的那次布局才会把新尺寸落到 frame 上。
  /// 不挂 window 时 `layoutIfNeeded()` 只会重新询问尺寸、不会重排子视图,修没修都停在一行,
  /// 测试就没有判别力了(已实测)。
  ///
  /// 判别力:删掉 setter 里的 invalidateIntrinsicContentSize(),高度停在一行,本测试变红。
  func testTextChangeUpdatesAutoLayoutHeight() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
    window.isHidden = false
    let container = UIView(frame: window.bounds)
    window.addSubview(container)
    let label = SwiftyLabel("x")
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      label.topAnchor.constraint(equalTo: container.topAnchor),
      label.widthAnchor.constraint(equalToConstant: 200),
    ])
    window.layoutIfNeeded()
    let oneLine = label.frame.height

    label.text = String(repeating: "a much longer piece of text that should wrap ", count: 4)
    window.layoutIfNeeded()

    XCTAssertGreaterThan(
      label.frame.height, oneLine * 2,
      "文本变成多行后,Auto Layout 给出的高度必须随之增长(实得 \(label.frame))")
  }

  /// intrinsicContentSize 与 sizeThatFits / draw 必须是同一个口径。
  ///
  /// intrinsicContentSize 曾用 `NSAttributedString.boundingRect` 计算,看不到 TextKit
  /// 容器上的 numberOfLines、padding(lineFragmentPadding)、lineBreakMode:实测
  /// numberOfLines = 1、宽 100 时它给出 (82, 251),sizeThatFits 给出 (98, 17) ——
  /// Auto Layout 分到一个十几行高的框,draw 却只画一行、居中。
  ///
  /// 还没布局过(bounds 宽为 0)时按不限宽量:以 0 为换行宽度会让每个词各占一行。
  ///
  /// 判别力:改回 boundingRect 的实现,第一条断言就失败。
  func testIntrinsicContentSizeMatchesSizeThatFits() {
    let text = String(repeating: "wrap me please ", count: 10)
    let unlimited = CGFloat.greatestFiniteMagnitude

    let label = SwiftyLabel(text)
    label.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
    label.numberOfLines = 1
    XCTAssertEqual(
      label.intrinsicContentSize, label.sizeThatFits(CGSize(width: 100, height: unlimited)),
      "numberOfLines = 1 时应只有一行高")

    label.numberOfLines = 0
    label.padding = 8
    XCTAssertEqual(
      label.intrinsicContentSize, label.sizeThatFits(CGSize(width: 100, height: unlimited)),
      "padding 必须计入")

    let unsized = SwiftyLabel(text)
    XCTAssertEqual(
      unsized.intrinsicContentSize,
      unsized.sizeThatFits(CGSize(width: unlimited, height: unlimited)),
      "尚未布局时应按不限宽量出单行尺寸")
  }

  /// sizeToFit() 的结果等于按当前宽度(未布局时不限宽)量出的 sizeThatFits。
  ///
  /// 锁住行为用:sizeToFit 曾先调 super(内部按 bounds 量一次)再按新宽度量第二次,
  /// 两次的结果实测总是相同,已简化为一次。
  func testSizeToFitMatchesSizeThatFits() {
    let text = String(repeating: "wrap me please ", count: 10)
    let unlimited = CGFloat.greatestFiniteMagnitude

    let unsized = SwiftyLabel(text)
    let expectedUnsized = unsized.sizeThatFits(CGSize(width: unlimited, height: unlimited))
    unsized.sizeToFit()
    XCTAssertEqual(unsized.frame.size, expectedUnsized)

    let sized = SwiftyLabel(text)
    sized.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
    let expectedSized = sized.sizeThatFits(CGSize(width: 100, height: unlimited))
    sized.sizeToFit()
    XCTAssertEqual(sized.frame.size, expectedSized)
  }

  func testExplicitAttributesSurviveMerge() {
    // 调用方在 attributedText 中显式指定的颜色不应被 textColor 覆盖。
    //
    // 断言必须读 mergedAttributedText,不能读 attributedText:后者是调用方设置的
    // 源数据,merge 只在一份拷贝上操作、从不写回源数据,所以读 attributedText
    // 无论 merge 对不对都会“通过”,测不出回归。
    let label = SwiftyLabel()
    label.textColor = .black
    label.attributedText = NSAttributedString(
      string: "red",
      attributes: [.foregroundColor: UIColor.red]
    )
    label.frame = CGRect(x: 0, y: 0, width: 100, height: 40)

    // 触发一次绘制,确认不崩溃
    UIGraphicsImageRenderer(size: label.bounds.size).image { _ in
      label.draw(label.bounds)
    }
    XCTAssertEqual(
      label.mergedAttributedText?.attribute(
        .foregroundColor,
        at: 0,
        effectiveRange: nil) as? UIColor,
      .red)
  }

  /// 局部重绘(`setNeedsDisplay(_:)` 只标脏一块)时,脏矩形内的像素必须与整体重绘一致。
  ///
  /// UIKit 传给 draw(_:) 的是**脏矩形**,不是 bounds。draw 曾经拿它当文本容器的尺寸、
  /// 也拿它算对齐,于是局部重绘时整段文本被重新排进那一小块里,与周围已有的像素错位。
  ///
  /// 判别力:把 draw 里的 bounds.size 改回 rect.size,脏矩形内几十个采样点对不上。
  func testPartialRedrawMatchesFullRedraw() {
    let label = SwiftyLabel("Hello world", .black, .white)
    label.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
    let dirty = CGRect(x: 0, y: 0, width: 100, height: 40)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    func render(_ rect: CGRect) -> UIImage {
      UIGraphicsImageRenderer(size: label.bounds.size, format: format).image { ctx in
        UIColor.white.setFill()
        ctx.fill(label.bounds)
        ctx.cgContext.clip(to: rect)
        label.draw(rect)
      }
    }
    let full = render(label.bounds)
    let partial = render(dirty)

    let fullPixels = Self.pixels(of: full, in: dirty)
    XCTAssertFalse(fullPixels.isEmpty, "前提:取到了像素")
    XCTAssertTrue(fullPixels.contains { $0 < 128 }, "前提:脏矩形里确实画了文字,否则本测试无判别力")
    XCTAssertEqual(fullPixels, Self.pixels(of: partial, in: dirty), "脏矩形内的像素应与整体重绘逐字节一致")
  }

  /// 把 image 的 rect 区域重绘进一块固定格式(RGBA8)的缓冲区,返回全部字节。
  /// 不能直接读 `cropping(to:)` 结果的 dataProvider:裁出来的图可能仍共用整张图的数据。
  private static func pixels(of image: UIImage, in rect: CGRect) -> [UInt8] {
    guard let crop = image.cgImage?.cropping(to: rect) else { return [] }
    let width = Int(rect.width)
    let height = Int(rect.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return [] }
    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
  }

  func testEmptyLabelDrawsWithoutCrashing() {
    let label = SwiftyLabel()
    label.frame = CGRect(x: 0, y: 0, width: 50, height: 20)
    UIGraphicsImageRenderer(size: label.bounds.size).image { _ in
      label.draw(label.bounds)
    }
  }

  // MARK: - 常驻文本存储的缓存不能过期

  /// 同一个 label 连续改属性,每一步的尺寸与绘制像素都必须与"用同样属性新建的 label"一致。
  ///
  /// 3.0 起 SwiftyLabel 常驻一份 NSTextStorage,属性变了才重建,不再每次绘制、每次量尺寸
  /// 都从头生成字形。这样做的风险是缓存过期没失效:改了字体却还按旧字体排版,改了行数
  /// 却还用旧的布局。新建的 label 没有任何缓存,是天然的参照。每一步都先让被测 label
  /// 量一遍、画一遍(把布局缓存起来),再改下一个属性。
  ///
  /// 判别力:去掉任一属性的"标记过期",或去掉容器属性变化后的布局失效,本测试变红。
  func testCachedLayoutMatchesFreshLabelAfterMutations() {
    let steps: [(String, (SwiftyLabel) -> Void)] = [
      ("长文本", { $0.text = String(repeating: "SwiftyLabel 缓存对拍 wrap me ", count: 6) }),
      ("单行", { $0.numberOfLines = 1 }),
      ("padding", { $0.padding = 8 }),
      ("按词换行", { $0.lineBreakMode = .byWordWrapping }),
      ("不限行数", { $0.numberOfLines = 0 }),
      ("字体", { $0.font = .systemFont(ofSize: 20) }),
      (
        "段落样式",
        {
          let style = NSMutableParagraphStyle()
          style.lineSpacing = 6
          $0.paragraphStyle = style
        }
      ),
      ("颜色", { $0.textColor = .red }),
      (
        "阴影",
        {
          let shadow = NSShadow()
          shadow.shadowOffset = CGSize(width: 1, height: 1)
          shadow.shadowBlurRadius = 2
          $0.shadow = shadow
        }
      ),
      (
        "显式属性串",
        {
          $0.attributedText = NSAttributedString(
            string: "显式颜色的属性串,也要换行 wrap wrap wrap wrap",
            attributes: [.foregroundColor: UIColor.blue])
        }
      ),
      ("空串", { $0.text = "" }),
      ("短文本", { $0.text = "回来" }),
      ("nil", { $0.text = nil }),
    ]
    let probes = [
      CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude),
      CGSize(width: 60, height: CGFloat.greatestFiniteMagnitude),
      CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
    ]
    let frame = CGRect(x: 0, y: 0, width: 120, height: 200)

    let label = SwiftyLabel(nil, .black, .white)
    label.frame = frame
    for index in steps.indices {
      let (name, apply) = steps[index]
      apply(label)

      let fresh = SwiftyLabel(nil, .black, .white)
      fresh.frame = frame
      for (_, earlier) in steps[...index] { earlier(fresh) }

      for probe in probes {
        XCTAssertEqual(
          label.sizeThatFits(probe), fresh.sizeThatFits(probe), "「\(name)」之后,按 \(probe) 量出的尺寸不一致")
      }
      XCTAssertEqual(
        label.intrinsicContentSize, fresh.intrinsicContentSize,
        "「\(name)」之后,intrinsicContentSize 不一致"
      )
      XCTAssertEqual(Self.render(label), Self.render(fresh), "「\(name)」之后,绘制出的像素不一致")
    }
  }

  /// 把 label 按自己的 bounds 画进一张 scale 为 1、白底的位图,返回全部字节。
  private static func render(_ label: SwiftyLabel) -> [UInt8] {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: label.bounds.size, format: format).image { ctx in
      UIColor.white.setFill()
      ctx.fill(label.bounds)
      label.draw(label.bounds)
    }
    return pixels(of: image, in: label.bounds)
  }
}
