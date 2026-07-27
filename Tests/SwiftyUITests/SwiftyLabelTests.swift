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

  func testEmptyLabelDrawsWithoutCrashing() {
    let label = SwiftyLabel()
    label.frame = CGRect(x: 0, y: 0, width: 50, height: 20)
    UIGraphicsImageRenderer(size: label.bounds.size).image { _ in
      label.draw(label.bounds)
    }
  }
}
