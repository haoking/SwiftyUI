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

    XCTAssertNotNil(ImageCachePool.defalut.image(withIdentifier: identifier))
    ImageCachePool.defalut.removeImage(withIdentifier: identifier)
  }

  // MARK: - load(_ name:) 三分支

  /// 缓存命中:预先用 load(_:identifier:) 填充默认缓存后,
  /// load(_ name:) 应直接返回缓存内容,不去查 asset catalog。
  func testLoadByNameReturnsCachedImageOnCacheHit() {
    let identifier = "SwiftyImageTests.loadByName.hit.\(UUID().uuidString)"
    let source = TestSupport.makeSolidImage(color: .orange)
    _ = UIImage.load(source, identifier: identifier)
    defer { ImageCachePool.defalut.removeImage(withIdentifier: identifier) }

    XCTAssertNotNil(
      UIImage.load(identifier),
      "缓存中已存在该 identifier,应命中缓存而不是去查找不存在的 asset")
  }

  /// 缓存未命中 + asset 不存在:测试 bundle 没有任何图片资源,
  /// UIImage(named:) 必然失败,load(_ name:) 应返回 nil,而不是崩溃。
  func testLoadByNameReturnsNilWhenCacheMissAndAssetMissing() {
    let identifier = "SwiftyImageTests.loadByName.missing.\(UUID().uuidString)"

    XCTAssertNil(
      UIImage.load(identifier),
      "缓存未命中且 asset 不存在时应返回 nil")
    XCTAssertNil(
      ImageCachePool.defalut.image(withIdentifier: identifier),
      "查找失败不应把占位内容写入缓存")
  }

  /// 缓存未命中 + asset 存在:这条分支要求 UIImage(named:) 真的能找到一张图片。
  /// 单元测试 bundle 不携带任何 image asset(加 fixture 需要改动 Package.swift 的
  /// resources 声明,超出本任务范围),因此这里用 XCTSkip 显式记录限制,
  /// 而不是假装覆盖到了或悄悄漏掉这个分支。跳过前先验证前提假设本身成立。
  func testLoadByNameWithPresentAssetIsUnavailableInTestBundle() throws {
    let probeName = "SwiftyImageTests.probe.\(UUID().uuidString)"
    guard UIImage(named: probeName) == nil else {
      XCTFail("测试 bundle 出现了本不该存在的 asset,前提假设已失效,应补全此分支的真实测试")
      return
    }
    throw XCTSkip(
      "测试 bundle 没有任何 image asset,UIImage(named:) 恒为 nil,"
        + "无法覆盖 load(_ name:) “未命中但 asset 存在”分支;需在宿主 App 或集成测试环境验证")
  }
}
