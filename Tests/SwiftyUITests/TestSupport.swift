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

  /// 生成一张能判别 getColors() 排序方向的图片。
  ///
  /// getColors() 只在 x∈[5,10] 这一竖条内采样背景色,因此颜色差异必须发生在
  /// 垂直方向上才能被区分。本夹具让左侧竖条上部 70% 为 majorityEdge、
  /// 下部 30% 为 minorityEdge,于是"出现最多的边缘色"与"最少的"明确不同。
  ///
  /// 右侧填一个亮色,使 primary 不会因候选集为空而落到 fallback。
  static func makeEdgeDiscriminatingImage(
    majorityEdge: UIColor,
    minorityEdge: UIColor,
    body: UIColor,
    size: CGSize = CGSize(width: 250, height: 250)
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      body.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      let stripWidth = size.width * 0.2  // 覆盖 x∈[5,10] 采样区
      majorityEdge.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: stripWidth, height: size.height * 0.7))
      minorityEdge.setFill()
      ctx.fill(CGRect(x: 0, y: size.height * 0.7, width: stripWidth, height: size.height * 0.3))
    }
  }
}
