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
}
