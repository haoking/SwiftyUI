//
//  SwiftyColor.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 9/28/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

extension UIColor {
  @inlinable
  @inline(__always)
  public static func load(_ R: CGFloat, _ G: CGFloat, _ B: CGFloat, _ A: CGFloat = 1.0) -> UIColor {
    return UIColor(red: R / 255.0, green: G / 255.0, blue: B / 255.0, alpha: A)
  }

  @inlinable
  @inline(__always)
  public static func hex(_ hex: UInt, _ A: CGFloat = 1.0) -> UIColor {
    // 在 UInt 上取位,不先转 Int:`Int(hex)` 对 ≥ 2^63 的输入会 trap。
    let r = CGFloat((hex >> 16) & 0xFF)
    let g = CGFloat((hex >> 8) & 0xFF)
    let b = CGFloat(hex & 0xFF)
    return load(r, g, b, A)
  }

  public final class func hex(_ hexString: String, _ alpha: CGFloat = 1.0) -> UIColor {
    var hex: String = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
    guard hex.count == 3 || hex.count == 6 else { return UIColor(white: 1.0, alpha: 0.0) }
    // 逐字符校验:UInt(_:radix:) 接受前导 "+"/"-","+FFFFF" 会被当成 0x0FFFFF。
    guard hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
      return UIColor(white: 1.0, alpha: 0.0)
    }
    if hex.count == 3 {
      for (index, char) in hex.enumerated() {
        hex.insert(char, at: hex.index(hex.startIndex, offsetBy: index * 2))
      }
    }
    // 长度合法不代表字符合法:"zzz" 会展开成 "zzzzzz",UInt(_:radix:) 返回 nil。
    // 原实现在此处强解包导致崩溃(B19)。
    guard let value = UInt(hex, radix: 16) else { return UIColor(white: 1.0, alpha: 0.0) }
    return .hex(value, alpha)
  }
}

extension UIColor {
  public final var redValue: CGFloat { return rgba().r }
  public final var greenValue: CGFloat { return rgba().g }
  public final var blueValue: CGFloat { return rgba().b }
  public final var alphaValue: CGFloat { return rgba().a }

  private final func rgba() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let components: [CGFloat]? = cgColor.components
    let numberOfComponents: Int = cgColor.numberOfComponents
    switch numberOfComponents {
    case 4:
      return (components![0], components![1], components![2], components![3])
    case 2:
      return (components![0], components![0], components![0], components![1])
    default:
      return (0, 0, 0, 1)
    }
  }

  // 下面几个判断各只取一次分量:redValue / greenValue / blueValue 每读一个都要
  // 重新取一遍 cgColor.components(每次分配一个数组),取色时对每个候选色都要调用。

  internal final var isDark: Bool {
    let c = rgba()
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
  }

  internal final var isBlackOrWhite: Bool {
    let c = rgba()
    return (c.r > 0.91 && c.g > 0.91 && c.b > 0.91) || (c.r < 0.09 && c.g < 0.09 && c.b < 0.09)
  }

  internal final func color(minSaturation: CGFloat) -> UIColor {
    var (hue, saturation, brightness, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (
      0.0, 0.0, 0.0, 0.0
    )
    getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    return saturation < minSaturation
      ? UIColor(hue: hue, saturation: minSaturation, brightness: brightness, alpha: alpha) : self
  }

  internal final func isDistinct(from color: UIColor) -> Bool {
    let threshold: CGFloat = 0.25
    let a = rgba()
    let b = color.rgba()

    guard abs(a.r - b.r) > threshold || abs(a.g - b.g) > threshold || abs(a.b - b.b) > threshold
    else { return false }

    // 两个颜色都接近灰度时,通道差异不足以说明它们"可区分"。
    // 原实现在此处赋 result = false 后又被无条件的 result = true 覆盖,
    // 整个判断形同虚设(B13)。
    let selfIsNearGray = abs(a.r - a.g) < 0.03 && abs(a.r - a.b) < 0.03
    let otherIsNearGray = abs(b.r - b.g) < 0.03 && abs(b.r - b.b) < 0.03
    if selfIsNearGray && otherIsNearGray { return false }

    return true
  }

  fileprivate final func isContrasting(with color: UIColor) -> Bool {
    let a = rgba()
    let b = color.rgba()
    let bgLum = 0.2126 * a.r + 0.7152 * a.g + 0.0722 * a.b
    let fgLum = 0.2126 * b.r + 0.7152 * b.g + 0.0722 * b.b
    let contrast = bgLum > fgLum ? (bgLum + 0.05) / (fgLum + 0.05) : (fgLum + 0.05) / (bgLum + 0.05)
    return 1.6 < contrast
  }
}

extension UIImage {
  /// 在后台线程分析图片主色,完成后**在主线程**回调。
  ///
  /// `complete` 标注为 `@MainActor`:回调在主线程执行是本方法对外的承诺
  /// (README 亦如此声明),标上之后这条承诺就能被类型系统表达,调用方可以
  /// 直接在回调里碰 UI:
  ///
  /// ```swift
  /// image.colors { bg, _, _, _ in
  ///   self.view.backgroundColor = bg   // 无需任何桥接
  /// }
  /// ```
  ///
  /// 另标 `@Sendable`:闭包本身要从调用线程投递到取色链条上再传回主队列。
  ///
  /// - Important: 取色链条出错或被取消时(例如 SwiftyThreadPool 收到内存
  ///   告警调用 removeAll()),`complete` **不会被调用**,且没有任何信号。
  ///   需要把失败与取消变成可见信号的调用方请改用 `colors() async throws`
  ///   —— 但它换来的只是"错误被抛出来"这一件事,不是"一定会有结果":
  ///   它继承了 `value()` 的全部三种挂死情形(见那里的文档注释)。
  public final func colors(
    _ complete: (
      @MainActor @Sendable (
        _ background: UIColor, _ primary: UIColor, _ secondary: UIColor, _ detail: UIColor
      ) -> Void
    )?
  ) {
    // 强捕获图片,不用 [weak self]:接收者常常是个临时值,弱捕获时它可能在任务开始
    // 之前就被释放,任务随之什么也不做、complete 永不调用。图片并不持有这条链,
    // 强捕获不会成环,只是让它活到分析结束。
    Promise<(UIColor, UIColor, UIColor, UIColor)>.firstly { (update, _) in
      update(self.getColors())
    }.then(on: .main) { (_, colors) in
      // Promise 是非隔离的调度原语,它的任务闭包是 @Sendable 的;而 `on: .main`
      // 保证这里确实跑在 OperationQueue.main 上。这一次 assumeIsolated 把该保证
      // 收进库内、只审这一处,调用方因此拿到一个静态可用的 @MainActor 回调,
      // 不必自己写桥接。性质同 SwiftyAlertView 中保留的那两处:
      // 受检的、有文档的、只审一次的边界。
      MainActor.assumeIsolated {
        if let complete = complete, let colors = colors {
          complete(colors.0, colors.1, colors.2, colors.3)
        }
      }
    }.catch()
  }

  /// 在后台线程分析图片主色,以 async/await 取回。
  ///
  /// 与回调版 `colors(_:)` 有**两条**区别:
  ///
  /// 1. **错误处理**:回调版以无参 `.catch()` 收尾,链条出错或被取消时回调
  ///    **不会被调用**,调用方拿不到任何信号;本方法则把错误抛出来。
  /// 2. **执行上下文**:回调版以 `.then(on: .main)` 保证回调在主线程执行
  ///    (那是它写在文档里的承诺);本方法**没有这个跳转**,await 在哪个上下文
  ///    发起就在哪个上下文恢复。从 @MainActor 处调用时结果自然回到主 actor,
  ///    下面的示例因此成立;从非隔离上下文调用则**不会**自动到主线程,
  ///    要碰 UIKit 请自己跳回去。
  ///
  /// 区别仅此两条 —— 尤其**不包括**"一定会返回",见下方第一条 Important。
  ///
  /// ```swift
  /// do {
  ///   let (bg, _, _, _) = try await image.colors()
  ///   view.backgroundColor = bg
  /// } catch {
  ///   view.backgroundColor = .systemBackground
  /// }
  /// ```
  ///
  /// - Important: 本方法**不是**回调版的"不会挂死版本"。它就是 `value()` 加一个
  ///   nil 检查,因此**继承了 `value()` 的全部三种挂死情形**(线程池被 stop()
  ///   后未 restart()、被 cancel() 过、或在挂起状态下被 removeAll()/cancel()
  ///   —— 见 `Promise.value()` 的文档注释,其中第三种在日常使用中够得着)。
  ///   取色链条走的是 `SwiftyThreadPool.default`,上述任一情形发生时这个
  ///   await 同样一直不返回。它相对回调版的收益只有一条:失败与取消从"静默"
  ///   变成"抛错"。需要"菊花一定会停"的调用方,请自己在外面加一层超时。
  /// - Throws: `PromiseError.cancelled` —— 取色链条**的任务**被取消(最常见的
  ///   来源是 SwiftyThreadPool 收到内存告警调用 removeAll())。
  /// - Throws: `PromiseError.noValue` —— 链条终结但没有产出值。按当前实现不会抛出:
  ///   await 期间接收者由调用方保活,下面的 weak self 守卫不会失败;没有位图可分析的
  ///   图片也会得到回落色而不是空值。保留它,只为不对 value() 的可选结果强解包。
  public final func colors() async throws -> (
    background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor
  ) {
    let promise = Promise<(UIColor, UIColor, UIColor, UIColor)>.firstly { [weak self] (update, _) in
      guard let strongSelf = self else { return }
      update(strongSelf.getColors())
    }
    guard let colors = try await promise.value() else {
      // value() 返回 nil 意味着没有任务调用过 update(...),在这里只可能是
      // 上面那个 weak self 守卫失败。不强解包 —— B1/B19 都是这么来的。
      throw PromiseError.noValue
    }
    return (colors.0, colors.1, colors.2, colors.3)
  }

  private final class CountedColor {
    let color: UIColor
    let count: Int
    /// 像素的 0xRRGGBB 打包值,只用于次数相同时的排序,让结果与字典的遍历顺序无关。
    let key: UInt32

    init(color: UIColor, count: Int, key: UInt32) {
      self.color = color
      self.count = count
      self.key = key
    }
  }

  private final func getColors() -> (
    background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor
  ) {
    // 没有位图可分析(零尺寸的 UIImage() 之类)时,按"一个可用颜色都找不到"处理,
    // 取值与下方算法在那种情形下的回落值相同。原来这里是 `.cgImage!`,在线程池的
    // 后台线程上 trap —— 同 B1/B19 的强解包。
    let noColors: (UIColor, UIColor, UIColor, UIColor) = (.black, .white, .white, .white)
    let r_width: CGFloat = 250
    let targetHeight = r_width / (size.width / size.height)
    guard targetHeight.isFinite, targetHeight > 0 else { return noColors }

    // 下采样到 scale 为 1、恰好 250px 宽的位图。曾经借用 reSize(to:),它按**屏幕** scale
    // 出图(@3x 设备上 750px 宽):像素量是设计值的 9 倍,而下方 x∈[5,10] 的背景采样带
    // 随 scale 落在图上不同的位置,同一张图在不同设备上取出不同的颜色。
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = isOpaque
    format.preferredRange = .standard
    let targetSize = CGSize(width: r_width, height: targetHeight)
    let downsampled = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let cgImage = downsampled.cgImage else { return noColors }

    let width: Int = cgImage.width
    let height: Int = cgImage.height
    let bytesPerRow: Int = width * 4
    let randomColorsThreshold: Int = Int(CGFloat(height) * 0.01)
    let blackColor: UIColor = .black
    let whiteColor: UIColor = .white
    // 必须清零:透明像素以 source-over 画上去等于什么都没写,malloc 的残留内容
    // (通常是上一次取色的位图)会被当成像素读出来。
    guard let raw = calloc(height, bytesPerRow) else { return noColors }
    defer { free(raw) }
    guard
      let context = CGContext(
        data: raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
    else { return noColors }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    let pixels = raw.assumingMemoryBound(to: UInt8.self)

    // 像素打包成 0xRRGGBB 计数,只为出现过的颜色建 UIColor。曾经每个像素都新建一个
    // UIColor 放进 NSCountedSet(靠 UIColor 的 hash / isEqual 去重),按列遍历行优先的
    // 缓冲区。像素格式是 ARGB(premultipliedFirst),字节 1…3 是 R、G、B。
    var edgeCounts: [UInt32: Int] = [:]
    var imageCounts: [UInt32: Int] = [:]
    for y in 0..<height {
      let row = pixels + y * bytesPerRow
      for x in 0..<width {
        let pixel = row + x * 4
        let key = UInt32(pixel[1]) << 16 | UInt32(pixel[2]) << 8 | UInt32(pixel[3])
        imageCounts[key, default: 0] += 1
        if x >= 5 && x <= 10 {
          edgeCounts[key, default: 0] += 1
        }
      }
    }
    func color(of key: UInt32) -> UIColor {
      .load(CGFloat((key >> 16) & 0xFF), CGFloat((key >> 8) & 0xFF), CGFloat(key & 0xFF))
    }

    // B6: sort(by:) 要求严格弱序,原实现传 <= 属未定义行为。
    // B12(排序方向): 该算法要把"出现次数最多"的边缘色当作背景色,
    //                 因此这里必须是降序,取 .first 得到最常见的颜色。
    // 次数相同时按打包值排:字典的遍历顺序逐进程随机,不加这一条结果就不确定。
    let sortComparator: (CountedColor, CountedColor) -> Bool = { (a, b) -> Bool in
      a.count != b.count ? a.count > b.count : a.key < b.key
    }

    var sortedColors: [CountedColor] = edgeCounts.compactMap { key, count in
      count >= randomColorsThreshold ? CountedColor(color: color(of: key), count: count, key: key) : nil
    }

    sortedColors.sort(by: sortComparator)

    var proposedEdgeColor: CountedColor = .init(color: blackColor, count: 1, key: 0)

    if let first = sortedColors.first { proposedEdgeColor = first }

    if proposedEdgeColor.color.isBlackOrWhite && !sortedColors.isEmpty {
      // B12: 原实现写作 CGFloat(countedColor.count / proposedEdgeColor.count),
      //      先做整数除法再转 CGFloat,结果非 0 即 >= 1,0.3 这个阈值形同虚设。
      for countedColor in sortedColors
      where CGFloat(countedColor.count) / CGFloat(proposedEdgeColor.count) > 0.3 {
        if !countedColor.color.isBlackOrWhite {
          proposedEdgeColor = countedColor
          break
        }
      }
    }

    let imageBackgroundColor: UIColor = proposedEdgeColor.color
    let isDarkBackgound: Bool = imageBackgroundColor.isDark

    // 候选色按原色的出现次数计:曾用提饱和之后新建的颜色去查计数,那个颜色图里从没
    // 出现过,灰色系恒为 0。
    sortedColors = imageCounts.compactMap { key, count in
      let candidate = color(of: key).color(minSaturation: 0.15)
      guard candidate.isDark == !isDarkBackgound else { return nil }
      return CountedColor(color: candidate, count: count, key: key)
    }

    sortedColors.sort(by: sortComparator)

    var primaryColor: UIColor?
    var secondaryColor: UIColor?
    var detailColor: UIColor?

    for countedColor in sortedColors {
      let color: UIColor = countedColor.color
      if primaryColor == nil && color.isContrasting(with: imageBackgroundColor) {
        primaryColor = color
      } else if secondaryColor == nil && primaryColor != nil
        && primaryColor!.isDistinct(from: color) && color.isContrasting(with: imageBackgroundColor)
      {
        secondaryColor = color
      } else if secondaryColor != nil
        && (secondaryColor!.isDistinct(from: color) && primaryColor!.isDistinct(from: color)
          && color.isContrasting(with: imageBackgroundColor))
      {
        detailColor = color
        break
      }
    }

    return (
      imageBackgroundColor, primaryColor ?? (isDarkBackgound ? whiteColor : blackColor),
      secondaryColor ?? (isDarkBackgound ? whiteColor : blackColor),
      detailColor ?? (isDarkBackgound ? whiteColor : blackColor)
    )
  }
}
extension UIColor {
  public final class var infoSystem: UIColor { return .load(47.0, 112.0, 225.0) }
  public final class var successSystem: UIColor { return .load(83.0, 215.0, 106.0) }
  public final class var warningSystem: UIColor { return .load(221.0, 170.0, 59.0) }
  public final class var dangerSystem: UIColor { return .load(229.0, 0.0, 15.0) }
}
