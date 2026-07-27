import UIKit

/// 测试公用工具。所有测试图片都在内存中确定性生成,不依赖任何资源文件。
enum TestSupport {

  /// 生成一张纯色图片。
  static func makeSolidImage(
    color: UIColor,
    size: CGSize = CGSize(width: 32, height: 32)
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      color.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }

  /// 生成一张左右两色的图片,用于取色算法测试。
  /// 左半宽度占 40%,右半占 60%,因此右色是出现次数更多的一方。
  static func makeTwoToneImage(
    left: UIColor,
    right: UIColor,
    size: CGSize = CGSize(width: 100, height: 100)
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      left.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: size.width * 0.4, height: size.height))
      right.setFill()
      ctx.fill(CGRect(x: size.width * 0.4, y: 0, width: size.width * 0.6, height: size.height))
    }
  }
}
