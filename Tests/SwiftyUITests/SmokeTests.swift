import UIKit
import XCTest

@testable import SwiftyUI

final class SmokeTests: XCTestCase {

  /// 验证 @testable import 生效、UIKit 可用、测试能在模拟器上跑起来。
  func testHarnessIsWired() {
    let color = UIColor.hex(0xCCFF00)
    XCTAssertEqual(color.redValue, 204.0 / 255.0, accuracy: 0.001)
    XCTAssertEqual(color.greenValue, 1.0, accuracy: 0.001)
    XCTAssertEqual(color.blueValue, 0.0, accuracy: 0.001)
  }

  /// 验证 TestSupport 能生成图片。
  func testSupportProducesImages() {
    let image = TestSupport.makeSolidImage(color: .red)
    XCTAssertEqual(image.size, CGSize(width: 32, height: 32))
    XCTAssertNotNil(image.cgImage)
  }
}
