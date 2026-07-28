//
//  SwiftyColor.swift
//  WHCWSIFT
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
    let mask: Int = 0xFF
    let r = CGFloat(Int(hex >> 16) & mask)
    let g = CGFloat(Int(hex >> 8) & mask)
    let b = CGFloat(Int(hex) & mask)
    return load(r, g, b, A)
  }

  public final class func hex(_ hexString: String, _ alpha: CGFloat = 1.0) -> UIColor {
    var hex: String = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
    guard hex.count == 3 || hex.count == 6 else { return UIColor(white: 1.0, alpha: 0.0) }
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

  internal final var isDark: Bool {
    return (0.2126 * redValue + 0.7152 * greenValue + 0.0722 * blueValue) < 0.5
  }

  internal final var isBlackOrWhite: Bool {
    return (redValue > 0.91 && greenValue > 0.91 && blueValue > 0.91)
      || (redValue < 0.09 && greenValue < 0.09 && blueValue < 0.09)
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

    guard
      abs(redValue - color.redValue) > threshold
        || abs(greenValue - color.greenValue) > threshold
        || abs(blueValue - color.blueValue) > threshold
    else { return false }

    // 两个颜色都接近灰度时,通道差异不足以说明它们"可区分"。
    // 原实现在此处赋 result = false 后又被无条件的 result = true 覆盖,
    // 整个判断形同虚设(B13)。
    let selfIsNearGray = abs(redValue - greenValue) < 0.03 && abs(redValue - blueValue) < 0.03
    let otherIsNearGray =
      abs(color.redValue - color.greenValue) < 0.03 && abs(color.redValue - color.blueValue) < 0.03
    if selfIsNearGray && otherIsNearGray { return false }

    return true
  }

  fileprivate final func isContrasting(with color: UIColor) -> Bool {
    let bgLum = 0.2126 * redValue + 0.7152 * greenValue + 0.0722 * blueValue
    let fgLum = 0.2126 * color.redValue + 0.7152 * color.greenValue + 0.0722 * color.blueValue
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
    Promise<(UIColor, UIColor, UIColor, UIColor)>.firstly { [weak self] (update, _) in

      guard let strongSelf = self else { return }
      update(strongSelf.getColors())

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
  /// - Throws: `PromiseError.noValue` —— 链条终结但没有产出值。正常情况下
  ///   不会发生;它对应 self 在分析开始前就被释放这一理论情形。
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

    init(color: UIColor, count: Int) {
      self.color = color
      self.count = count
    }
  }

  private final func getColors() -> (
    background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor
  ) {
    let ratio: CGFloat = size.width / size.height
    let r_width: CGFloat = 250
    let cgImage: CGImage = reSize(to: CGSize(width: r_width, height: r_width / ratio)).cgImage!

    let width: Int = cgImage.width
    let height: Int = cgImage.height
    let bytesPerPixel: Int = 4
    let bytesPerRow: Int = width * bytesPerPixel
    let bitsPerComponent: Int = 8
    let randomColorsThreshold: Int = Int(CGFloat(height) * 0.01)
    let blackColor: UIColor = .black
    let whiteColor: UIColor = .white
    let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let raw: UnsafeMutableRawPointer = malloc(bytesPerRow * height)
    let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue
    let context: CGContext? = CGContext(
      data: raw, width: width, height: height, bitsPerComponent: bitsPerComponent,
      bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    let data: UnsafePointer<UInt8>? = UnsafePointer<UInt8>(
      context?.data?.assumingMemoryBound(to: UInt8.self))
    let imageBackgroundColors: NSCountedSet = NSCountedSet(capacity: height)
    let imageColors: NSCountedSet = NSCountedSet(capacity: width * height)

    // B6: sort(by:) 要求严格弱序,原实现传 <= 属未定义行为。
    // B12(排序方向): 该算法要把"出现次数最多"的边缘色当作背景色,
    //                 因此这里必须是降序,取 .first 得到最常见的颜色。
    let sortComparator: (CountedColor, CountedColor) -> Bool = { (a, b) -> Bool in
      return a.count > b.count
    }

    for x in 0..<width {
      for y in 0..<height {
        let pixel: Int = ((width * y) + x) * bytesPerPixel
        let color: UIColor = .load(
          CGFloat((data?[pixel + 1])!), CGFloat((data?[pixel + 2])!), CGFloat((data?[pixel + 3])!))
        if x >= 5 && x <= 10 {
          imageBackgroundColors.add(color)
        }

        imageColors.add(color)
      }
    }

    var sortedColors: [CountedColor] = []

    for (_, color) in imageBackgroundColors.enumerated() {
      guard let color = color as? UIColor else { continue }
      let colorCount: Int = imageBackgroundColors.count(for: color)
      if randomColorsThreshold <= colorCount {
        sortedColors.append(CountedColor(color: color, count: colorCount))
      }
    }

    sortedColors.sort(by: sortComparator)

    var proposedEdgeColor: CountedColor = .init(color: blackColor, count: 1)

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

    sortedColors.removeAll()

    for (_, imageColor) in imageColors.enumerated() {
      guard let imageColor = imageColor as? UIColor else { continue }
      let color = imageColor.color(minSaturation: 0.15)

      if color.isDark == (!isDarkBackgound) {
        let colorCount: Int = imageColors.count(for: color)
        sortedColors.append(CountedColor(color: color, count: colorCount))
      }
    }

    sortedColors.sort(by: sortComparator)

    var primaryColor: UIColor?
    var secondaryColor: UIColor?
    var detailColor: UIColor?

    for (_, countedColor) in sortedColors.enumerated() {
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

    free(raw)

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
