import UIKit
import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyImageViewTests: XCTestCase {

  func testImageAliasesBackgroundImage() {
    let image = TestSupport.makeSolidImage(color: .green)
    let view = SwiftyImageView(image)
    XCTAssertNotNil(view.image)
    XCTAssertTrue(view.image === view.backgroundImage)
  }

  /// B3:layer.contents 存放非 CGImage 时,读取不应崩溃
  func testReadingImageAfterLayerContentsTamperedDoesNotCrash() {
    let view = SwiftyImageView(TestSupport.makeSolidImage(color: .red))
    view.layer.contents = "not an image"
    XCTAssertNotNil(view.image, "读取应返回持有的原始 UIImage,而不是从 layer 反推")
  }

  func testSettingNilClearsLayerContents() {
    let view = SwiftyImageView(TestSupport.makeSolidImage(color: .red))
    view.image = nil
    XCTAssertNil(view.layer.contents)
  }

  /// 同 SwiftyButtonTests.testInitPushesBackgroundImageToLayer 的保护,针对
  /// SwiftyImageView —— 它当前是安全的(init 经 image 计算属性间接赋值,
  /// 观察器会触发),本测试确保将来有人把它改成直接赋值自有存储属性时能被发现。
  func testImageViewInitPushesImageToLayer() {
    let image = TestSupport.makeSolidImage(color: .green)
    let view = SwiftyImageView(image)
    XCTAssertNotNil(view.layer.contents, "init 设置的图片必须到达 layer.contents")
  }

  // MARK: - 上屏的内容必须与 UIImage 的绘制语义一致

  /// 带方向信息的图片(相机照片的 EXIF 方向就是这种)必须按方向显示。
  ///
  /// layer.contents 只认 CGImage,而 CGImage 不携带 imageOrientation。曾经直接把
  /// `image.cgImage` 挂上去,方向被整个丢掉:竖拍的照片横着显示。B3 修的是"读回来
  /// 丢了 orientation",这里是同一件事的另一半 —— 显示时丢了它。
  ///
  /// 期望值取自 `UIImage.draw(in:)`,那是 UIKit 对"这张图该长什么样"的定义。
  /// 夹具:2×1 位图左红右蓝,标成 `.right`(显示时顺时针转 90°)后应显示为上红下蓝。
  ///
  /// 判别力:改回 `layer.contents = image?.cgImage`,采样点期望红、实得蓝。
  func testNonUpOrientationIsDisplayedAsUIKitDrawsIt() throws {
    let base = Self.render(size: CGSize(width: 2, height: 1)) { ctx in
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      UIColor.blue.setFill()
      ctx.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
    }
    let rotated = UIImage(cgImage: try XCTUnwrap(base.cgImage), scale: 1, orientation: .right)
    XCTAssertEqual(rotated.size, CGSize(width: 1, height: 2), "前提:.right 让显示尺寸宽高对调")

    let size = CGSize(width: 10, height: 20)
    let expected = Self.render(size: size) { _ in
      rotated.draw(in: CGRect(origin: .zero, size: size))
    }
    let view = SwiftyImageView(rotated)
    view.frame = CGRect(origin: .zero, size: size)
    let actual = Self.render(size: size) { ctx in view.layer.render(in: ctx.cgContext) }

    // 右上角:按方向显示是红色(上半),丢了方向则是蓝色(右半)
    XCTAssertEqual(Self.pixel(actual, x: 8, y: 5), Self.pixel(expected, x: 8, y: 5))
    XCTAssertEqual(Self.pixel(actual, x: 8, y: 15), Self.pixel(expected, x: 8, y: 15))
  }

  /// 没有 CGImage 的图片(Core Image 滤镜的输出常常以 `UIImage(ciImage:)` 包装)也要显示出来。
  ///
  /// 这种 UIImage 的 `cgImage` 为 nil,曾经 layer.contents 因此被置空,视图一片空白
  /// —— UIImageView 能正常显示同一张图,而 SwiftyImageView 的定位正是它的替代品。
  ///
  /// 判别力:让 layerContents 在方向为 .up 时无条件返回 cgImage,采样点是白底而不是红色。
  func testImageWithoutCGImageIsDisplayed() {
    let ci = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
      .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    let image = UIImage(ciImage: ci)
    XCTAssertNil(image.cgImage, "前提:CIImage 背书的 UIImage 没有 cgImage,否则本测试无判别力")

    let view = SwiftyImageView(image)
    view.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
    let actual = Self.render(size: view.bounds.size) { ctx in view.layer.render(in: ctx.cgContext) }

    XCTAssertNotNil(view.layer.contents)
    XCTAssertEqual(Self.pixel(actual, x: 2, y: 2), [255, 0, 0], "应显示红色,而不是露出白底")
  }

  // MARK: - 工具

  private static func render(
    size: CGSize, _ draw: (UIGraphicsImageRendererContext) -> Void
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      UIColor.white.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      draw(ctx)
    }
  }

  /// 取一个像素的 RGB(0...255)。
  private static func pixel(_ image: UIImage, x: Int, y: Int) -> [Int] {
    guard let cgImage = image.cgImage,
      let crop = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
    else { return [] }
    var bytes = [UInt8](repeating: 0, count: 4)
    guard
      let context = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return [] }
    context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return bytes.prefix(3).map(Int.init)
  }
}
