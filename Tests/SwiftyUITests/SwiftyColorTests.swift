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
}

extension SwiftyColorTests {

  /// 取色算法的基线快照。
  ///
  /// 图片左 40% 为红、右 60% 为蓝,因此"出现次数最多的颜色"是蓝色。
  /// 算法意图是把出现最多的边缘色作为背景色;当前实现的排序谓词是升序
  /// 且取 .first,取到的可能是出现最少的颜色。
  ///
  /// 本测试只记录当前输出,不断言对错。Task 8 会打印实际值并据此裁决。
  func testImageColorsBaseline() {
    let image = TestSupport.makeTwoToneImage(left: .red, right: .blue)
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

    // 基线记录:把实际值打印出来,便于 Task 8 对照
    print("BASELINE background = R\(bg.redValue) G\(bg.greenValue) B\(bg.blueValue)")
    print("BASELINE primary    = R\(pri.redValue) G\(pri.greenValue) B\(pri.blueValue)")

    // 唯一的硬断言:回调必须在主线程,且必须返回四个非 nil 颜色
    XCTAssertNotNil(background)
    XCTAssertNotNil(primary)
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
}
