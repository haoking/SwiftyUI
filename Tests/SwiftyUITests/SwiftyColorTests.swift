import UIKit
import XCTest

@testable import SwiftyUI

final class SwiftyColorTests: XCTestCase {

  // MARK: - hex 数值形式

  func testHexFromUInt() {
    let color = UIColor.hex(0xCCFF00)
    XCTAssertEqual(color.redValue, 204.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(color.greenValue, 1.0, accuracy: 0.001)
    XCTAssertEqual(color.blueValue, 0.0, accuracy: 0.001)
    XCTAssertEqual(color.alphaValue, 1.0, accuracy: 0.001)
  }

  func testHexFromUIntWithAlpha() {
    XCTAssertEqual(UIColor.hex(0x000000, 0.5).alphaValue, 0.5, accuracy: 0.001)
  }

  // MARK: - hex 字符串形式

  func testHexFromSixDigitString() {
    let color = UIColor.hex("336699")
    XCTAssertEqual(color.redValue, 51.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(color.greenValue, 102.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(color.blueValue, 153.0 / 255.0, accuracy: 0.001)
  }

  func testHexFromThreeDigitStringExpands() {
    // "f00" 应展开为 "ff0000"
    let color = UIColor.hex("f00")
    XCTAssertEqual(color.redValue, 1.0, accuracy: 0.001)
    XCTAssertEqual(color.greenValue, 0.0, accuracy: 0.001)
    XCTAssertEqual(color.blueValue, 0.0, accuracy: 0.001)
  }

  func testHexStripsLeadingHash() {
    XCTAssertEqual(
      UIColor.hex("#f00").redValue,
      UIColor.hex("f00").redValue,
      accuracy: 0.001)
  }

  func testHexWithInvalidLengthReturnsTransparent() {
    // 长度既不是 3 也不是 6,返回全透明白色
    let color = UIColor.hex("12345")
    XCTAssertEqual(color.alphaValue, 0.0, accuracy: 0.001)
  }

  /// B19:非十六进制字符不应导致崩溃。
  func testHexWithNonHexCharactersReturnsTransparent() {
    XCTAssertEqual(UIColor.hex("zzz").alphaValue, 0.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.hex("gggggg").alphaValue, 0.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.hex("#nothex").alphaValue, 0.0, accuracy: 0.001)
  }

  // MARK: - rgba 取值

  func testRGBAFromGrayscaleColorSpace() {
    // 2 分量色彩空间(白+alpha),三个通道应取同一个值
    let gray = UIColor(white: 0.5, alpha: 0.8)
    XCTAssertEqual(gray.redValue, 0.5, accuracy: 0.001)
    XCTAssertEqual(gray.greenValue, 0.5, accuracy: 0.001)
    XCTAssertEqual(gray.blueValue, 0.5, accuracy: 0.001)
    XCTAssertEqual(gray.alphaValue, 0.8, accuracy: 0.001)
  }

  // MARK: - 语义色

  func testSystemSemanticColors() {
    XCTAssertEqual(UIColor.infoSystem.redValue, 47.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.successSystem.greenValue, 215.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.warningSystem.blueValue, 59.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.dangerSystem.redValue, 229.0 / 255.0, accuracy: 0.001)
  }

  // MARK: - B13 回归

  func testIsDistinctReturnsFalseForNearlyIdenticalColors() {
    let a = UIColor.hex(0x808080)
    let b = UIColor.hex(0x828282)
    XCTAssertFalse(a.isDistinct(from: b), "通道差异未超阈值,不应判为可区分")
  }

  func testIsDistinctReturnsFalseWhenBothAreNearGray() {
    // 两者通道差异超过 0.25,但都接近灰度
    let darkGray = UIColor(white: 0.15, alpha: 1.0)
    let lightGray = UIColor(white: 0.85, alpha: 1.0)
    XCTAssertFalse(
      darkGray.isDistinct(from: lightGray),
      "两者都接近灰度时不应判为可区分(B13)")
  }

  func testIsDistinctReturnsTrueForDifferentHues() {
    XCTAssertTrue(UIColor.hex(0xFF0000).isDistinct(from: UIColor.hex(0x0000FF)))
  }
}

extension SwiftyColorTests {

  /// getColors() 背景采样的确定性回归(control case)。
  ///
  /// 与 brief 原始设想不同:本测试**不能**用来验证 B6/B12 的排序方向。
  /// 原因(Task 3 在 task-3-report.md "Fix Round 1/5" 中已证实,本次运行
  /// 再次实测确认):getColors() 的背景采样只读取 resize 后 250px 宽位图中
  /// x∈[5,10] 这一条边缘竖条(SwiftyColor.swift 内 imageBackgroundColors
  /// 的采集逻辑),而测试图左 40% 红对应 x∈[0,100),该竖条完全落在红色区域
  /// 内、只包含红色一种颜色。sortedColors 因此只有一个元素,.first 与升序
  /// /降序无关——背景色在排序修正前后都是纯红,这是已验证的不变量,而不是
  /// "蓝色因为是多数色而被选中"。实测:降序修正后 background 仍为
  /// R1.0 G0.0 B0.0,与 Task 2/3 记录的原始基线完全一致。
  ///
  /// 真正能区分排序方向的回归见下面的 testImageColorsSortDirectionBaseline
  /// (使用 makeEdgeDiscriminatingImage,背景采样条带本身就有两种颜色)。
  /// 本测试的价值在于把原先的"仅打印基线"升级为硬断言,锁定这条边缘采样
  /// 路径修复后依然稳定、可复现。
  func testImageColorsPicksMostCommonAsBackground() {
    let image = TestSupport.makeTwoToneImage(left: .red, right: .blue)
    let done = expectation(description: "colors 回调")

    var background: UIColor?
    image.colors { bg, _, _, _ in
      background = bg
      done.fulfill()
    }
    wait(for: [done], timeout: 10.0)

    let bg = try! XCTUnwrap(background)
    XCTAssertGreaterThan(
      bg.redValue, 0.5, "背景采样条带 x∈[5,10] 完全落在红色区域内,只有红色一种颜色")
    XCTAssertLessThan(bg.blueValue, 0.5)
  }

  /// 回调必须在主线程(README 明确承诺)。
  func testImageColorsCallsBackOnMainThread() {
    let image = TestSupport.makeSolidImage(color: .green, size: CGSize(width: 64, height: 64))
    let done = expectation(description: "colors 回调")
    var wasMainThread = false

    image.colors { _, _, _, _ in
      wasMainThread = Thread.isMainThread
      done.fulfill()
    }

    wait(for: [done], timeout: 10.0)
    XCTAssertTrue(wasMainThread, "colors 的回调必须在主线程")
  }

  /// 排序方向的判别性基线。
  ///
  /// 与 testImageColorsPicksMostCommonAsBackground 不同(那个测试的采样
  /// 条带内只有一种颜色,无法区分排序方向),本夹具能真正区分升序/降序:
  /// 边缘采样条带内深蓝占 70%、深红占 30%,若排序为降序则背景色应为深蓝
  /// (出现最多),若为升序则为深红(出现最少)。
  ///
  /// B12 裁决结果(Task 8):修正前(升序)background = 深红(minorityEdge,
  /// 出现最少),修正后(降序)background = 深蓝(majorityEdge,出现最多)。
  /// 证实原实现排序方向确实颠倒,已在 Sources/SwiftyColor.swift 中改为降序。
  /// 本测试仍只做 print + 非 nil 断言,不对具体 RGB 值做硬编码断言,避免
  /// 把浮点量化误差(如 0.55×255=140.25→140/255)锁进断言里。
  func testImageColorsSortDirectionBaseline() {
    let image = TestSupport.makeEdgeDiscriminatingImage(
      majorityEdge: UIColor(red: 0, green: 0, blue: 0.55, alpha: 1),
      minorityEdge: UIColor(red: 0.55, green: 0, blue: 0, alpha: 1),
      body: UIColor(red: 1, green: 1, blue: 0.6, alpha: 1)
    )
    let done = expectation(description: "colors 回调")
    var background: UIColor?
    var primary: UIColor?
    image.colors { bg, pri, _, _ in
      background = bg
      primary = pri
      done.fulfill()
    }
    wait(for: [done], timeout: 10.0)

    let bg = try! XCTUnwrap(background)
    let pri = try! XCTUnwrap(primary)
    print("BASELINE-SORT background = R\(bg.redValue) G\(bg.greenValue) B\(bg.blueValue)")
    print("BASELINE-SORT primary    = R\(pri.redValue) G\(pri.greenValue) B\(pri.blueValue)")

    XCTAssertNotNil(background)
    XCTAssertNotNil(primary)
  }
}
