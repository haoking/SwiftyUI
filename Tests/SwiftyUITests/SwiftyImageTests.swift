import UIKit
import XCTest

@testable import SwiftyUI

final class SwiftyImageTests: XCTestCase {

  // MARK: - 缩放

  func testResizeToExactSize() {
    let source = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 100, height: 50))
    let resized = source.reSize(to: CGSize(width: 40, height: 40))
    XCTAssertEqual(resized.size, CGSize(width: 40, height: 40))
  }

  func testResizeWithZeroSizeReturnsSelf() {
    let source = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 100, height: 50))
    XCTAssertEqual(source.reSize(to: .zero).size, source.size)
    XCTAssertEqual(source.reSize(toFit: .zero).size, source.size)
    XCTAssertEqual(source.reSize(toFill: .zero).size, source.size)
  }

  func testResizeToFitProducesCanvasSize() {
    // toFit 输出画布尺寸,内容按比例居中,四周留白
    let source = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 100, height: 50))
    let fitted = source.reSize(toFit: CGSize(width: 60, height: 60))
    XCTAssertEqual(fitted.size, CGSize(width: 60, height: 60))
  }

  func testResizeToFillProducesCanvasSize() {
    let source = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 100, height: 50))
    let filled = source.reSize(toFill: CGSize(width: 60, height: 60))
    XCTAssertEqual(filled.size, CGSize(width: 60, height: 60))
  }

  // MARK: - 圆角

  func testRoundedPreservesSize() {
    let source = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 40, height: 40))
    XCTAssertEqual(source.rounded(withCornerRadius: 8).size, source.size)
  }

  func testRoundedIntoCircleProducesSquare() {
    let source = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 100, height: 50))
    let circular = source.roundedIntoCircle()
    XCTAssertEqual(
      circular.size.width, circular.size.height,
      "非正方形输入应先裁成正方形")
  }

  // MARK: - opaque 判定

  func testOpaqueDetection() {
    // UIGraphicsImageRendererFormat.opaque = true 产生无 alpha 通道的位图
    let opaque = TestSupport.makeTwoToneImage(
      left: .red, right: .blue,
      size: CGSize(width: 20, height: 20))
    XCTAssertTrue(opaque.isOpaque)

    let transparent = TestSupport.makeSolidImage(color: UIColor.red.withAlphaComponent(0.5))
    XCTAssertFalse(transparent.isOpaque)
  }

  // MARK: - inflate

  func testInflateIsIdempotent() {
    let image = TestSupport.makeSolidImage(color: .red)
    image.inflate()
    image.inflate()  // 第二次应直接返回,不应崩溃
    XCTAssertNotNil(image.cgImage)
  }

  // MARK: - 缓存装载

  func testLoadWithIdentifierPopulatesDefaultCache() {
    let identifier = "SwiftyImageTests.load.\(UUID().uuidString)"
    let source = TestSupport.makeSolidImage(color: .green)

    XCTAssertNotNil(UIImage.load(source, identifier: identifier))

    let settle = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
    wait(for: [settle], timeout: 3.0)

    XCTAssertNotNil(ImageCachePool.defalut.image(withIdentifier: identifier))
    ImageCachePool.defalut.removeImage(withIdentifier: identifier)
  }
}
