import UIKit

// 2.1.0 的取色算法(Sources/SwiftyColor.swift 里的 getColors()),原样搬来做对拍参照。
//
// 3.0 把计数换成了一次扫描的开放寻址表、把候选色改成按序惰性求值,四个结果必须与这里逐个相等。
// 它用到的判定函数也一并冻结在本文件里(加 ref 前缀),不调用库里的同名函数 ——
// 否则库里的判定一旦被改动,两边会一起变,对拍就测不出来了。
// 不要"顺手"把这里改得和新实现一样:它的价值就在于不变。

extension UIImage {
  func referenceColors() -> (
    background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor
  ) {
    let noColors: (UIColor, UIColor, UIColor, UIColor) = (.black, .white, .white, .white)
    let r_width: CGFloat = 250
    let targetHeight = r_width / (size.width / size.height)
    guard targetHeight.isFinite, targetHeight > 0 else { return noColors }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = refIsOpaque
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
      UIColor(
        red: CGFloat((key >> 16) & 0xFF) / 255.0, green: CGFloat((key >> 8) & 0xFF) / 255.0,
        blue: CGFloat(key & 0xFF) / 255.0, alpha: 1.0)
    }

    let sortComparator: (ReferenceCountedColor, ReferenceCountedColor) -> Bool = { a, b in
      a.count != b.count ? a.count > b.count : a.key < b.key
    }

    var sortedColors: [ReferenceCountedColor] = edgeCounts.compactMap { key, count in
      count >= randomColorsThreshold
        ? ReferenceCountedColor(color: color(of: key), count: count, key: key) : nil
    }
    sortedColors.sort(by: sortComparator)

    var proposedEdgeColor = ReferenceCountedColor(color: blackColor, count: 1, key: 0)
    if let first = sortedColors.first { proposedEdgeColor = first }

    if proposedEdgeColor.color.refIsBlackOrWhite && !sortedColors.isEmpty {
      for countedColor in sortedColors
      where CGFloat(countedColor.count) / CGFloat(proposedEdgeColor.count) > 0.3 {
        if !countedColor.color.refIsBlackOrWhite {
          proposedEdgeColor = countedColor
          break
        }
      }
    }

    let imageBackgroundColor: UIColor = proposedEdgeColor.color
    let isDarkBackgound: Bool = imageBackgroundColor.refIsDark

    sortedColors = imageCounts.compactMap { key, count in
      let candidate = color(of: key).refColor(minSaturation: 0.15)
      guard candidate.refIsDark == !isDarkBackgound else { return nil }
      return ReferenceCountedColor(color: candidate, count: count, key: key)
    }
    sortedColors.sort(by: sortComparator)

    var primaryColor: UIColor?
    var secondaryColor: UIColor?
    var detailColor: UIColor?

    for countedColor in sortedColors {
      let color: UIColor = countedColor.color
      if primaryColor == nil && color.refIsContrasting(with: imageBackgroundColor) {
        primaryColor = color
      } else if secondaryColor == nil && primaryColor != nil
        && primaryColor!.refIsDistinct(from: color)
        && color.refIsContrasting(with: imageBackgroundColor)
      {
        secondaryColor = color
      } else if secondaryColor != nil
        && (secondaryColor!.refIsDistinct(from: color) && primaryColor!.refIsDistinct(from: color)
          && color.refIsContrasting(with: imageBackgroundColor))
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

extension UIImage {
  /// 2.1.0 的 UIImage.isOpaque:只有确知没有 alpha 通道时才算不透明。
  fileprivate var refIsOpaque: Bool {
    switch cgImage?.alphaInfo {
    case .none?, .noneSkipFirst?, .noneSkipLast?:
      return true
    default:
      return false
    }
  }
}

private final class ReferenceCountedColor {
  let color: UIColor
  let count: Int
  let key: UInt32

  init(color: UIColor, count: Int, key: UInt32) {
    self.color = color
    self.count = count
    self.key = key
  }
}

extension UIColor {
  fileprivate func refRGBA() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let components: [CGFloat]? = cgColor.components
    switch cgColor.numberOfComponents {
    case 4:
      return (components![0], components![1], components![2], components![3])
    case 2:
      return (components![0], components![0], components![0], components![1])
    default:
      return (0, 0, 0, 1)
    }
  }

  fileprivate var refIsDark: Bool {
    let c = refRGBA()
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
  }

  fileprivate var refIsBlackOrWhite: Bool {
    let c = refRGBA()
    return (c.r > 0.91 && c.g > 0.91 && c.b > 0.91) || (c.r < 0.09 && c.g < 0.09 && c.b < 0.09)
  }

  fileprivate func refColor(minSaturation: CGFloat) -> UIColor {
    var (hue, saturation, brightness, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return saturation < minSaturation
      ? UIColor(hue: hue, saturation: minSaturation, brightness: brightness, alpha: alpha) : self
  }

  fileprivate func refIsDistinct(from color: UIColor) -> Bool {
    let threshold: CGFloat = 0.25
    let a = refRGBA()
    let b = color.refRGBA()
    guard abs(a.r - b.r) > threshold || abs(a.g - b.g) > threshold || abs(a.b - b.b) > threshold
    else { return false }
    let selfIsNearGray = abs(a.r - a.g) < 0.03 && abs(a.r - a.b) < 0.03
    let otherIsNearGray = abs(b.r - b.g) < 0.03 && abs(b.r - b.b) < 0.03
    if selfIsNearGray && otherIsNearGray { return false }
    return true
  }

  fileprivate func refIsContrasting(with color: UIColor) -> Bool {
    let a = refRGBA()
    let b = color.refRGBA()
    let bgLum = 0.2126 * a.r + 0.7152 * a.g + 0.0722 * a.b
    let fgLum = 0.2126 * b.r + 0.7152 * b.g + 0.0722 * b.b
    let contrast = bgLum > fgLum ? (bgLum + 0.05) / (fgLum + 0.05) : (fgLum + 0.05) / (bgLum + 0.05)
    return 1.6 < contrast
  }
}
