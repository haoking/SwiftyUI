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

  /// 零尺寸输入不应崩溃。
  ///
  /// `UIImage()` 的 size 是 .zero,此时 UIGraphicsBeginImageContextWithOptions
  /// 根本不会创建 context,UIGraphicsGetImageFromCurrentImageContext() 返回 nil。
  /// 这两个方法原本对它强解包,而同文件里三个兄弟 reSize 方法都先做了尺寸守卫
  /// (testResizeWithZeroSizeReturnsSelf 覆盖的就是那三个)。
  ///
  /// 判别力:去掉守卫或把 `?? self` 改回 `!`,本测试会让测试进程直接 crash。
  func testRoundedWithZeroSizeReturnsSelfWithoutCrashing() {
    let empty = UIImage()
    XCTAssertEqual(empty.size, .zero, "前提:UIImage() 的尺寸为零,否则本测试无判别力")

    XCTAssertEqual(
      empty.rounded(withCornerRadius: 5).size, .zero,
      "零尺寸时 rounded(withCornerRadius:) 应原样返回,不应 trap")
    XCTAssertEqual(
      empty.rounded(withCornerRadius: 5, divideRadiusByImageScale: true).size, .zero)
    XCTAssertEqual(
      empty.roundedIntoCircle().size, .zero,
      "零尺寸时 roundedIntoCircle() 应原样返回,不应 trap")
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

    XCTAssertNotNil(ImageCachePool.default.image(withIdentifier: identifier))
    ImageCachePool.default.removeImage(withIdentifier: identifier)
  }

  // MARK: - load(_ name:) 三分支

  /// 缓存命中:预先用 load(_:identifier:) 填充默认缓存后,
  /// load(_ name:) 应直接返回缓存内容,不去查 asset catalog。
  func testLoadByNameReturnsCachedImageOnCacheHit() {
    let identifier = "SwiftyImageTests.loadByName.hit.\(UUID().uuidString)"
    let source = TestSupport.makeSolidImage(color: .orange)
    _ = UIImage.load(source, identifier: identifier)
    defer { ImageCachePool.default.removeImage(withIdentifier: identifier) }

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
      ImageCachePool.default.image(withIdentifier: identifier),
      "查找失败不应把占位内容写入缓存")
  }

  // MARK: - B14 回归

  /// B14:1.x 的四个 `UIImage.load` 每次调用都现场 `let lock = NSLock()` 造一把
  /// **局部**锁再 lock/unlock。局部锁提供不了任何互斥 —— 每个调用者锁的是自己
  /// 那把,纯属开销。真正需要互斥的共享状态在 ImageCachePool 内部,由它那把
  /// **共享**锁保护(B4)。2.0 直接删掉了这些局部锁。
  ///
  /// 删除本身是纯开销移除,没有留下可断言的行为;能锁住的是这次删除所依赖的
  /// 那条前提:`UIImage.load` 的并发安全由 ImageCachePool 的共享锁提供。
  /// 本测试并发跑 load 的写路径与读路径,断言写进去的每一项都还在、且能读出。
  ///
  /// 判别力(已实测):去掉 ImageCachePool 的 lock,本测试崩溃;此时再把 1.x
  /// 那把局部锁加回 UIImage.load,依然崩溃 —— 那正是 B14 的论点。
  func testConcurrentLoadIsSerializedByTheCachePoolLock() {
    let prefix = "SwiftyImageTests.b14.\(UUID().uuidString)"
    let keyCount = 40
    let cache = ImageCachePool.default
    defer {
      for index in 0..<keyCount { cache.removeImage(withIdentifier: "\(prefix).\(index)") }
    }

    let image = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 8, height: 8))
    DispatchQueue.concurrentPerform(iterations: 400) { index in
      let identifier = "\(prefix).\(index % keyCount)"
      _ = UIImage.load(image, identifier: identifier)  // 写路径:inflate + add
      _ = UIImage.load(identifier)  // 读路径:命中缓存
    }

    for index in 0..<keyCount {
      XCTAssertNotNil(
        UIImage.load("\(prefix).\(index)"),
        "并发写入的第 \(index) 项应当仍在缓存里 —— 丢失说明缓存写入没有被真正串行化")
    }
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
