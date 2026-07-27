import UIKit
import XCTest

@testable import SwiftyUI

final class ImageCachePoolTests: XCTestCase {

  private var cache: ImageCachePool!

  override func setUp() {
    super.setUp()
    cache = ImageCachePool()
  }

  override func tearDown() {
    cache.removeAllImages()
    cache = nil
    super.tearDown()
  }

  // MARK: - 基本存取

  func testAddThenFetch() {
    let image = TestSupport.makeSolidImage(color: .red)
    cache.add(image, withIdentifier: "red")

    XCTAssertNotNil(cache.image(withIdentifier: "red"))
    XCTAssertNil(cache.image(withIdentifier: "missing"))
  }

  func testRemoveImage() {
    let image = TestSupport.makeSolidImage(color: .blue)
    cache.add(image, withIdentifier: "blue")

    XCTAssertTrue(cache.removeImage(withIdentifier: "blue"))
    XCTAssertFalse(cache.removeImage(withIdentifier: "blue"), "重复移除应返回 false")
    XCTAssertNil(cache.image(withIdentifier: "blue"))
  }

  func testRemoveAllImages() {
    cache.add(TestSupport.makeSolidImage(color: .red), withIdentifier: "a")
    cache.add(TestSupport.makeSolidImage(color: .blue), withIdentifier: "b")

    XCTAssertTrue(cache.removeAllImages())
    XCTAssertFalse(cache.removeAllImages(), "空缓存再次清空应返回 false")
    XCTAssertEqual(cache.memoryUsage, 0)
  }

  // MARK: - 内存计数

  func testMemoryUsageReflectsAddedImage() {
    // 32x32 @ scale 1,4 字节/像素 = 4096 字节
    let image = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 32, height: 32))
    cache.add(image, withIdentifier: "sized")

    XCTAssertEqual(cache.memoryUsage, 4096)
  }

  func testDefaultCapacities() {
    XCTAssertEqual(cache.memoryCapacity, 100_000_000)
    XCTAssertEqual(cache.preferredMemoryUsage, 60_000_000)
  }

  // MARK: - B4 / B5 回归

  /// B4:并发读写不应产生数据竞争或计数漂移。
  /// 当前实现用并发队列 + sync 做写操作,这个测试会不稳定地失败或崩溃。
  func testConcurrentAccessKeepsCountsConsistent() {
    let image = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 8, height: 8))
    let perImageBytes: UInt64 = 8 * 8 * 4  // 256

    DispatchQueue.concurrentPerform(iterations: 200) { index in
      let key = "concurrent-\(index % 20)"
      if index % 3 == 0 {
        self.cache.removeImage(withIdentifier: key)
      } else {
        self.cache.add(image, withIdentifier: key)
      }
      _ = self.cache.image(withIdentifier: key)
    }

    // 无论并发顺序如何,内存计数必须等于当前实际驻留的图片数 * 单张字节数
    let usage = cache.memoryUsage
    XCTAssertEqual(
      usage % perImageBytes, 0,
      "内存计数出现漂移,说明存在竞争(B4/B5)")
    XCTAssertLessThanOrEqual(usage, perImageBytes * 20)
  }

  /// B5:反复增删不应导致 UInt64 下溢 trap。
  func testRepeatedAddRemoveDoesNotUnderflow() {
    let image = TestSupport.makeSolidImage(color: .blue, size: CGSize(width: 8, height: 8))
    for _ in 0..<50 {
      cache.add(image, withIdentifier: "churn")
      cache.removeImage(withIdentifier: "churn")
    }
    XCTAssertEqual(cache.memoryUsage, 0)
  }

  /// LRU:超出容量时应优先淘汰最久未访问的条目。
  func testLRUEvictsLeastRecentlyAccessed() {
    // 8x8 = 256 字节/张。容量设为 3 张,目标使用量 2 张。
    cache.memoryCapacity = 256 * 3
    cache.preferredMemoryUsage = 256 * 2

    let image = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 8, height: 8))
    cache.add(image, withIdentifier: "a")
    cache.add(image, withIdentifier: "b")
    cache.add(image, withIdentifier: "c")

    // 访问 a,使 b 成为最久未访问者
    _ = cache.image(withIdentifier: "a")

    // 再加一张,触发淘汰
    cache.add(image, withIdentifier: "d")

    XCTAssertNotNil(cache.image(withIdentifier: "a"), "刚访问过的 a 不应被淘汰")
    XCTAssertNotNil(cache.image(withIdentifier: "d"), "刚加入的 d 不应被淘汰")
    XCTAssertNil(cache.image(withIdentifier: "b"), "最久未访问的 b 应被淘汰")
  }
}
