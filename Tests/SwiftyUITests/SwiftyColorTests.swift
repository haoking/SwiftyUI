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

  /// 超过 24 位的输入只取低 24 位,与三个通道各自 `& 0xFF` 的既有语义一致,不能 trap。
  ///
  /// 蓝色通道曾写作 `Int(hex) & mask`:`hex` ≥ 2^63 时 `Int(_:)` 装不下,
  /// 直接 "Not enough bits to represent the passed value"。红绿两个通道先右移再转换,
  /// 所以只有蓝色这一处会崩。
  func testHexFromUIntKeepsLow24BitsWithoutTrapping() {
    let color = UIColor.hex(UInt.max)
    XCTAssertEqual(color.redValue, 1.0, accuracy: 0.001)
    XCTAssertEqual(color.greenValue, 1.0, accuracy: 0.001)
    XCTAssertEqual(color.blueValue, 1.0, accuracy: 0.001)

    let masked = UIColor.hex(0xAB00_0000_0033_6699)
    XCTAssertEqual(masked.redValue, 51.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(masked.greenValue, 102.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(masked.blueValue, 153.0 / 255.0, accuracy: 0.001)
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

  /// 带正负号的串不是合法的十六进制颜色,同样返回全透明白色。
  ///
  /// 解析交给 `UInt(_:radix:)`,而它接受前导 "+"(也接受 "-0"):"+FFFFF" 长度是 6,
  /// 曾被当成 0x0FFFFF 返回一个颜色。
  ///
  /// 判别力:去掉逐字符的十六进制校验,前两条断言得到不透明颜色。
  func testHexWithSignCharactersReturnsTransparent() {
    XCTAssertEqual(UIColor.hex("+FFFFF").alphaValue, 0.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.hex("-00000").alphaValue, 0.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.hex("#+FF").alphaValue, 0.0, accuracy: 0.001)
  }

  /// 十六进制串解析的边界。3.0 起直接在 UTF-8 字节上解析,接受与拒绝的规则必须与
  /// 2.x 逐条相同。
  ///
  /// 判别力:放过全角数字(`Character.isHexDigit` 对它们为 true)、多剥一个 "#"、
  /// 或者把空白当分隔符跳过,都会让对应那一条变红。
  func testHexParsingEdgeCases() {
    XCTAssertEqual(UIColor.hex("AbC"), UIColor.hex("aabbcc"), "大小写混用的三位串应展开成六位")
    XCTAssertEqual(UIColor.hex("#AbCdEf").redValue, 0xAB / 255.0, accuracy: 0.001)
    XCTAssertEqual(UIColor.hex("#AbCdEf").blueValue, 0xEF / 255.0, accuracy: 0.001)
    for bad in [
      "", "#", "##fff", " fff", "fff ", "ff f", "ab\r\n", "１２３", "#１２３４５６", "e\u{301}ee",
      "\u{1F600}ab",
    ] {
      XCTAssertEqual(
        UIColor.hex(bad).alphaValue, 0, accuracy: 0.001, "应拒绝 \(bad.debugDescription)")
    }
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
  /// 原因(2.0 改造的 Task 3 实测证实,之后再次复测确认;当时的任务报告未入库):
  /// getColors() 的背景采样只读取 resize 后位图中像素坐标 x∈[5,10] 这一条边缘竖条
  /// (SwiftyColor.swift 内 imageBackgroundColors 的采集逻辑)。那张位图固定是
  /// scale 为 1、250px 宽(与设备无关,见 testBackgroundStripIsMeasuredOn250PixelBitmap),
  /// 测试图左 40% 的红色对应 x∈[0,100),该竖条完全落在红色区域
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

  /// 调用方不再持有图片时,回调也必须照常到达。
  ///
  /// `image.colors { … }` 的接收者经常是个临时值(`UIImage(data:)` 的结果、
  /// 一个局部变量)。取色任务曾经只 `[weak self]` 捕获图片:任务真正开始之前
  /// 图片就被释放的话,任务什么也不做,回调永不调用,且没有任何信号 —— 文档只把
  /// "出错或被取消"列为不回调的情形,这一条不在其中。图片并不持有这条链,强捕获
  /// 不会成环。
  ///
  /// 为了让"任务开始之前图片已释放"确定发生,先挂起共享线程池(取色链条只走
  /// `SwiftyThreadPool.default`,没有注入口),丢掉图片后再恢复。`defer` 保证无论
  /// 成败都恢复这个进程级单例,不污染后面的测试。
  ///
  /// 判别力:把捕获改回 `[weak self]`,本测试等满 10 秒超时变红。
  func testImageColorsCallsBackEvenWhenCallerDropsImage() {
    let pool = SwiftyThreadPool.default
    pool.stop()
    defer { pool.restart() }

    let done = expectation(description: "colors 回调")
    autoreleasepool {
      let image = TestSupport.makeSolidImage(color: .green, size: CGSize(width: 64, height: 64))
      image.colors { _, _, _, _ in done.fulfill() }
    }

    pool.restart()
    wait(for: [done], timeout: 10.0)
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
  /// 本测试必须失败(已实测验证;当时的任务报告未入库)。用不等式
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

  /// B12(整数除法)的真正回归 —— 此前**从未被任何测试触发过**。
  ///
  /// 出问题的那行(SwiftyColor.swift 里 `CGFloat(countedColor.count) /
  /// CGFloat(proposedEdgeColor.count) > 0.3`)位于
  /// `proposedEdgeColor.color.isBlackOrWhite` 分支内,而在本测试之前的每一个
  /// 夹具,主导边缘色都是彩色,该分支从不进入:把那行还原成
  /// `CGFloat(countedColor.count / proposedEdgeColor.count)` 的整数除法形式,
  /// 整套测试仍然全绿。这正是"测试通过但什么都没保护"的典型。
  ///
  /// 本测试补上缺的那个夹具:边缘采样条带里 70% 是纯白(命中 isBlackOrWhite,
  /// 从而真正进入那条分支),30% 是深蓝。
  ///
  /// - 浮点除法(正确):1350/3150 ≈ 0.43 > 0.3,深蓝通过筛选且不是黑白,
  ///   被选为背景色。
  /// - 整数除法(缺陷):sortedColors 已按出现次数降序,除首元素外整数商恒为 0,
  ///   `where` 直接把深蓝排除;而首元素就是纯白自己,`!isBlackOrWhite` 不成立,
  ///   循环空转,背景色停留在纯白 —— 0.3 这个阈值形同虚设。
  func testImageColorsReplacesBlackOrWhiteEdgeWithChromaticColor() {
    let image = TestSupport.makeEdgeDiscriminatingImage(
      majorityEdge: .white,
      minorityEdge: UIColor(red: 0.15, green: 0.2, blue: 0.9, alpha: 1),
      body: UIColor(red: 0.55, green: 0.55, blue: 0.2, alpha: 1)
    )
    let done = expectation(description: "colors 回调")
    let background = Box<UIColor?>(nil)
    image.colors { bg, _, _, _ in
      background.value = bg
      done.fulfill()
    }
    wait(for: [done], timeout: 10.0)

    let bg = try! XCTUnwrap(background.value)
    XCTAssertGreaterThan(
      bg.blueValue, 0.5,
      "主导边缘色是纯白时,应换用比例超过 0.3 的彩色边缘色(深蓝)作为背景色")
    XCTAssertLessThan(
      bg.redValue, 0.5,
      "背景色若仍是纯白,说明那行又变回了整数除法,0.3 的阈值形同虚设(B12)")
  }

  /// 背景采样带是 250px 宽下采样位图上的第 5–10 列,与设备屏幕 scale 无关。
  ///
  /// getColors 曾借用 reSize(to:) 下采样,那是按**屏幕** scale 出图:@3x 设备上位图有
  /// 750px 宽,像素量是 250px 设计值的 9 倍,而第 5–10 列在图上的位置随 scale 移动 ——
  /// 同一张图在不同设备上取出不同的背景色。
  ///
  /// 夹具:250pt 宽,左侧 4pt 红、其余蓝。在 250px 位图上第 5–10 列全是蓝;
  /// 在 @3x 的 750px 位图上,第 5–10 列只对应 1.7–3.7pt,落在红里。
  ///
  /// 判别力:改回按屏幕 scale 下采样,在 scale > 1 的模拟器上背景色是红。
  @MainActor
  func testBackgroundStripIsMeasuredOn250PixelBitmap() async throws {
    XCTAssertGreaterThan(UIScreen.main.scale, 1, "前提:屏幕 scale > 1,否则本测试无判别力")
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: 250, height: 250)
    let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      UIColor.blue.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 250))
    }

    let result = try await withTestTimeout { try await image.colors() }

    XCTAssertGreaterThan(result.background.blueValue, 0.9, "采样带应落在蓝色区域")
    XCTAssertLessThan(result.background.redValue, 0.1, "采样带不应落在左侧 4pt 的红色里")
  }

  /// 候选色按真实出现次数排序:低饱和的多数色不能因为计数查错而垫底。
  ///
  /// 候选循环先把颜色提到最低饱和度 0.15 再入选,计数却曾用**提饱和之后**的新颜色去查
  /// —— 那个颜色从没在图里出现过,灰色系的计数恒为 0,再多也排到最后。
  ///
  /// 夹具:左侧深蓝边带(背景),其余 70% 浅灰、30% 浅粉。浅灰出现得多,应当是主色
  /// (提饱和后约为 (0.8, 0.68, 0.68));计数查错时主色会变成浅粉 (1, 0.7, 0.8)。
  ///
  /// 判别力:改回用提饱和后的颜色查计数,主色的红色分量是 1.0。
  func testPrimaryColorIsTheMostFrequentEvenWhenDesaturated() async throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: CGSize(width: 250, height: 250), format: format)
      .image { ctx in
        UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1).setFill()
        ctx.fill(CGRect(x: 50, y: 0, width: 200, height: 175))
        UIColor(red: 1, green: 0.7, blue: 0.8, alpha: 1).setFill()
        ctx.fill(CGRect(x: 50, y: 175, width: 200, height: 75))
        UIColor(red: 0, green: 0, blue: 0.3, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 250))
      }

    let result = try await withTestTimeout { try await image.colors() }

    XCTAssertLessThan(result.primary.redValue, 0.9, "主色应是占多数的浅灰,而不是浅粉")
    XCTAssertEqual(
      result.primary.greenValue, result.primary.blueValue, accuracy: 0.05, "浅灰提饱和后绿蓝分量相等")
  }

  /// 透明像素按"透明黑"参与统计,不能读到上一次分析留下的内存。
  ///
  /// 像素缓冲区曾用 malloc 分配(内容未初始化),透明像素以 source-over 画上去等于什么
  /// 都没写,读出来的是那块内存里残留的东西 —— 通常是上一次取色刚释放的位图。
  /// 带透明底的图标、PNG 因此得到随机的背景色。
  ///
  /// 夹具:先分析一张纯绿图(同样尺寸的缓冲区随即被释放),再分析一张全透明图。
  ///
  /// 判别力:把缓冲区改回 malloc,全透明图的背景色读成残留的绿色。
  func testTransparentPixelsDoNotReadUninitializedMemory() async throws {
    let green = TestSupport.makeSolidImage(color: .green, size: CGSize(width: 64, height: 64))
    _ = try await withTestTimeout { try await green.colors() }

    let clear = TestSupport.makeSolidImage(color: .clear, size: CGSize(width: 64, height: 64))
    let result = try await withTestTimeout { try await clear.colors() }

    XCTAssertLessThan(result.background.greenValue, 0.1, "全透明图的背景应按透明黑统计,而不是残留的绿色")
    XCTAssertLessThan(result.background.redValue, 0.1)
    XCTAssertLessThan(result.background.blueValue, 0.1)
  }

  // MARK: - async 变体

  /// colors() 的 async 变体把四个颜色送了出来。
  ///
  /// 具体取值由既有的同步版本测试覆盖(testImageColors…),这里验证的是
  /// async 桥接本身:能返回、不抛错、四个分量都在。
  func testAsyncColorsReturnsFourColors() async throws {
    let image = TestSupport.makeEdgeDiscriminatingImage(
      majorityEdge: UIColor(red: 0, green: 0, blue: 0.55, alpha: 1),
      minorityEdge: UIColor(red: 0.55, green: 0, blue: 0, alpha: 1),
      body: UIColor(red: 1, green: 1, blue: 0.6, alpha: 1)
    )
    let result = try await withTestTimeout { try await image.colors() }

    // 与同步版本对同一张图的结论一致 —— 这一条才让测试有判别力:
    // 若 async 变体把颜色顺序搞错了,这里会红。
    //
    // 用 Box(TestSupport.swift 里既有的线程安全单值容器)取代原计划里的
    // Locked——本仓库测试目标里从未存在过 Locked 这个类型,Box 做的是同一件
    // 事(供异步回调安全地写回一个值),没有理由并存两个同构的帮助类型。
    let expected = Box<(UIColor, UIColor, UIColor, UIColor)?>(nil)
    let done = XCTestExpectation(description: "sync colors")
    image.colors { bg, p, s, d in
      expected.value = (bg, p, s, d)
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 20)

    let sync = try XCTUnwrap(expected.value)
    XCTAssertEqual(result.background, sync.0, "async 变体的 background 必须与同步版本一致")
    XCTAssertEqual(result.primary, sync.1, "async 变体的 primary 必须与同步版本一致")
    XCTAssertEqual(result.secondary, sync.2, "async 变体的 secondary 必须与同步版本一致")
    XCTAssertEqual(result.detail, sync.3, "async 变体的 detail 必须与同步版本一致")
  }

  // MARK: - 没有位图可分析

  /// 没有位图可分析的图片(零尺寸的 `UIImage()`)不能让取色崩溃。
  ///
  /// getColors() 第一步曾是 `reSize(to:).cgImage!`:零尺寸时 reSize 原样返回自己,
  /// 而 `UIImage()` 没有 CGImage,于是在线程池的后台线程上强解包 nil,整个进程崩溃
  /// —— 回调版与 async 版走的是同一条路径,这里用 async 版锁住。
  ///
  /// 现在按"一个可用颜色都找不到"处理,取值与算法在那种情形下的默认值相同:
  /// 边缘候选为空时背景色回落为黑,背景偏暗时另外三色回落为白。
  ///
  /// 判别力:把那行改回 `.cgImage!`,本测试所在的测试进程直接崩溃。
  func testColorsOfImageWithoutBitmapDoesNotCrash() async throws {
    let empty = UIImage()
    XCTAssertNil(empty.cgImage, "前提:UIImage() 没有 CGImage,否则本测试无判别力")

    let result = try await withTestTimeout { try await empty.colors() }

    XCTAssertEqual(result.background.redValue, 0, accuracy: 0.01, "无可用颜色时背景色应回落为黑")
    XCTAssertEqual(result.background.greenValue, 0, accuracy: 0.01)
    XCTAssertEqual(result.background.blueValue, 0, accuracy: 0.01)
    for (name, color) in [
      ("primary", result.primary), ("secondary", result.secondary), ("detail", result.detail),
    ] {
      XCTAssertEqual(color.redValue, 1, accuracy: 0.01, "\(name) 应回落为白")
      XCTAssertEqual(color.greenValue, 1, accuracy: 0.01, "\(name) 应回落为白")
      XCTAssertEqual(color.blueValue, 1, accuracy: 0.01, "\(name) 应回落为白")
    }
  }
}

// MARK: - 与 2.1.0 取色算法对拍

extension SwiftyColorTests {

  /// 取色结果必须与 2.1.0 的算法逐个相等(参照实现见 ColorExtractionReference.swift)。
  ///
  /// 3.0 把逐像素的字典计数换成了基数排序,把"给每一种颜色都建 UIColor 再排序"换成了
  /// 按次数从高到低逐个弹出、挑满就停。样本专门覆盖了几类容易出错的情形:颜色数接近
  /// 像素数的长尾(噪点、二维渐变)、次数完全打平只能靠键排序的(等宽两色、灰阶)、
  /// 边缘主色是黑白而要换成彩色的、透明与半透明、极端宽高比、带 scale 与方向的图。
  ///
  /// 判别力:把新实现里次数相同时的键序反过来、或漏掉 isDark 过滤,本测试变红。
  func testColorsMatchReferenceImplementation() async throws {
    for (name, image) in Self.equivalenceSamples() {
      let actual = try await withTestTimeout(60) { try await image.colors() }
      let expected = image.referenceColors()
      XCTAssertEqual(actual.background, expected.background, "\(name):background")
      XCTAssertEqual(actual.primary, expected.primary, "\(name):primary")
      XCTAssertEqual(actual.secondary, expected.secondary, "\(name):secondary")
      XCTAssertEqual(actual.detail, expected.detail, "\(name):detail")
    }
  }

  private static func equivalenceSamples() -> [(String, UIImage)] {
    let noise = makePixelImage(width: 64, height: 64) { _, _, rng in
      UInt32(truncatingIfNeeded: rng.next()) & 0xFF_FFFF
    }
    return [
      ("64×64 噪点", noise),
      (
        "250×250 二维渐变,每种颜色只出现一次",
        makePixelImage(width: 250, height: 250) { x, y, _ in
          UInt32(x) << 16 | UInt32(y) << 8 | UInt32((x + y) % 256)
        }
      ),
      (
        "250×250 灰阶,每种灰出现次数相同",
        makePixelImage(width: 250, height: 250) { x, _, _ in
          UInt32(x) * 0x01_0101
        }
      ),
      (
        "250×250 等宽两色,次数打平",
        makePixelImage(width: 250, height: 250) { x, _, _ in
          x < 125 ? 0x33_6699 : 0xCC_8844
        }
      ),
      (
        "250×250 八色调色板噪点",
        makePixelImage(width: 250, height: 250) { _, _, rng in
          [0xFF_0000, 0x00_FF00, 0x00_00FF, 0xFF_FF00, 0x00_FFFF, 0xFF_00FF, 0x80_8080, 0x20_2020][
            Int(rng.next() % 8)]
        }
      ),
      (
        "250×250 平滑起伏",
        makePixelImage(width: 250, height: 250) { x, y, _ in
          let r = UInt32(128 + 100 * sin(Double(x) / 20))
          let g = UInt32(128 + 100 * cos(Double(y) / 30))
          return r << 16 | g << 8 | UInt32((x * y) % 256)
        }
      ),
      ("双色", TestSupport.makeTwoToneImage(left: .red, right: .blue)),
      (
        "边缘蓝多红少",
        TestSupport.makeEdgeDiscriminatingImage(
          majorityEdge: UIColor(red: 0, green: 0, blue: 0.55, alpha: 1),
          minorityEdge: UIColor(red: 0.55, green: 0, blue: 0, alpha: 1),
          body: UIColor(red: 1, green: 1, blue: 0.6, alpha: 1))
      ),
      (
        "边缘白多蓝少",
        TestSupport.makeEdgeDiscriminatingImage(
          majorityEdge: .white,
          minorityEdge: UIColor(red: 0.15, green: 0.2, blue: 0.9, alpha: 1),
          body: UIColor(red: 0.55, green: 0.55, blue: 0.2, alpha: 1))
      ),
      ("全透明", TestSupport.makeSolidImage(color: .clear, size: CGSize(width: 64, height: 64))),
      (
        "半透明噪点",
        makePixelImage(width: 64, height: 64, randomAlpha: true) { _, _, rng in
          UInt32(truncatingIfNeeded: rng.next()) & 0xFF_FFFF
        }
      ),
      ("纯黑", TestSupport.makeSolidImage(color: .black, size: CGSize(width: 64, height: 64))),
      ("纯白", TestSupport.makeSolidImage(color: .white, size: CGSize(width: 64, height: 64))),
      (
        "20×400 细长噪点",
        makePixelImage(width: 20, height: 400) { _, _, rng in
          UInt32(truncatingIfNeeded: rng.next()) & 0xFF_FFFF
        }
      ),
      (
        "400×20 扁长噪点",
        makePixelImage(width: 400, height: 20) { _, _, rng in
          UInt32(truncatingIfNeeded: rng.next()) & 0xFF_FFFF
        }
      ),
      ("scale 3", UIImage(cgImage: noise.cgImage!, scale: 3, orientation: .up)),
      ("方向 .right", UIImage(cgImage: noise.cgImage!, scale: 1, orientation: .right)),
      ("没有位图", UIImage()),
    ]
  }

  /// 按像素生成一张 scale 为 1 的图。pixel 返回 0xRRGGBB;随机数发生器种子固定,
  /// 每次运行生成的图都相同。
  private static func makePixelImage(
    width: Int, height: Int, randomAlpha: Bool = false,
    _ pixel: (_ x: Int, _ y: Int, _ rng: inout SplitMix64) -> UInt32
  ) -> UIImage {
    var rng = SplitMix64(seed: UInt64(width * 7919 + height))
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let rgb = pixel(x, y, &rng)
        let offset = (y * width + x) * 4
        bytes[offset] = UInt8((rgb >> 16) & 0xFF)
        bytes[offset + 1] = UInt8((rgb >> 8) & 0xFF)
        bytes[offset + 2] = UInt8(rgb & 0xFF)
        bytes[offset + 3] = randomAlpha ? UInt8(truncatingIfNeeded: rng.next()) : 0xFF
      }
    }
    let alphaInfo: CGImageAlphaInfo = randomAlpha ? .last : .noneSkipLast
    let cgImage = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return UIImage(cgImage: cgImage)
  }
}
