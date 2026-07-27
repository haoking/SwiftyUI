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

  /// getColors() 背景采样只读取边缘竖条 x∈[5,10],不代表整张图片的多数色。
  ///
  /// 本测试**不能**用来验证 B6/B12 的排序方向。
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
  func testImageColorsBackgroundSamplesEdgeStripOnly() {
    let image = TestSupport.makeTwoToneImage(left: .red, right: .blue)
    let done = expectation(description: "colors 回调")

    let background = Box<UIColor?>(nil)
    image.colors { bg, _, _, _ in
      background.value = bg
      done.fulfill()
    }
    wait(for: [done], timeout: 10.0)

    let bg = try! XCTUnwrap(background.value)
    XCTAssertGreaterThan(
      bg.redValue, 0.5, "背景采样条带 x∈[5,10] 完全落在红色区域内,只有红色一种颜色")
    XCTAssertLessThan(bg.blueValue, 0.5)
  }

  /// 回调必须在主线程(README 明确承诺)。
  func testImageColorsCallsBackOnMainThread() {
    let image = TestSupport.makeSolidImage(color: .green, size: CGSize(width: 64, height: 64))
    let done = expectation(description: "colors 回调")
    let wasMainThread = Box(false)

    image.colors { _, _, _, _ in
      wasMainThread.value = Thread.isMainThread
      done.fulfill()
    }

    wait(for: [done], timeout: 10.0)
    XCTAssertTrue(wasMainThread.value, "colors 的回调必须在主线程")
  }

  /// 排序方向的判别性基线,并对方向本身做硬断言回归。
  ///
  /// 与 testImageColorsBackgroundSamplesEdgeStripOnly 不同(那个测试的采样
  /// 条带内只有一种颜色,无法区分排序方向),本夹具能真正区分升序/降序:
  /// 边缘采样条带内深蓝占 70%、深红占 30%,若排序为降序则背景色应为深蓝
  /// (出现最多),若为升序则为深红(出现最少)。
  ///
  /// B12 裁决结果(Task 8):修正前(升序)background = 深红(minorityEdge,
  /// 出现最少),修正后(降序)background = 深蓝(majorityEdge,出现最多)。
  /// 证实原实现排序方向确实颠倒,已在 Sources/SwiftyColor.swift 中改为降序。
  ///
  /// 本测试用不等式(而非精确相等)断言锁定这一方向:比较器改回升序时,
  /// 本测试必须失败(已实测验证,见 task-8-report.md 修复轮次 2)。用不等式
  /// 是为了不把浮点量化误差(如 0.55×255=140.25→140/255)锁进断言里,
  /// 同时仍然具备完整的方向判别力。
  func testImageColorsSortDirectionBaseline() {
    let image = TestSupport.makeEdgeDiscriminatingImage(
      majorityEdge: UIColor(red: 0, green: 0, blue: 0.55, alpha: 1),
      minorityEdge: UIColor(red: 0.55, green: 0, blue: 0, alpha: 1),
      body: UIColor(red: 1, green: 1, blue: 0.6, alpha: 1)
    )
    let done = expectation(description: "colors 回调")
    let background = Box<UIColor?>(nil)
    let primary = Box<UIColor?>(nil)
    image.colors { bg, pri, _, _ in
      background.value = bg
      primary.value = pri
      done.fulfill()
    }
    wait(for: [done], timeout: 10.0)

    let bg = try! XCTUnwrap(background.value)
    let pri = try! XCTUnwrap(primary.value)
    print("BASELINE-SORT background = R\(bg.redValue) G\(bg.greenValue) B\(bg.blueValue)")
    print("BASELINE-SORT primary    = R\(pri.redValue) G\(pri.greenValue) B\(pri.blueValue)")

    XCTAssertNotNil(background.value)
    XCTAssertNotNil(primary.value)

    // 方向敏感断言:降序取多数色(majorityEdge 深蓝 0,0,0.55),
    // 升序会取少数色(minorityEdge 深红 0.55,0,0)。
    // 用不等式而非精确相等,既能判别方向又不受浮点量化影响。
    XCTAssertGreaterThan(
      bg.blueValue, bg.redValue,
      "降序排序应选出现次数最多的 majorityEdge(深蓝)作为背景色;若这里偏红说明排序方向退回了升序(B6/B12)"
    )
    XCTAssertLessThan(
      bg.redValue, 0.1,
      "背景色不应是 minorityEdge(深红,R≈0.549)")

    // primary 应是 body 色(浅黄 1,1,0.6)。升序时它会是一个抗锯齿混合值
    // (Task 3 实测 R0.784 G0.749 B0.553),因为候选循环未应用
    // randomColorsThreshold,出现 1 次的边界像素会胜出。
    XCTAssertGreaterThan(
      pri.redValue, 0.9,
      "primary 应为 body 色浅黄;若明显低于 1.0 说明抗锯齿混合像素又胜出了")
    XCTAssertGreaterThan(pri.greenValue, 0.9)
  }
}
