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
}
