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

    // add 是异步 barrier,给它落地的时间
    let settle = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
    wait(for: [settle], timeout: 3.0)

    XCTAssertNotNil(cache.image(withIdentifier: "red"))
    XCTAssertNil(cache.image(withIdentifier: "missing"))
  }

  func testRemoveImage() {
    let image = TestSupport.makeSolidImage(color: .blue)
    cache.add(image, withIdentifier: "blue")

    let settle = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
    wait(for: [settle], timeout: 3.0)

    XCTAssertTrue(cache.removeImage(withIdentifier: "blue"))
    XCTAssertFalse(cache.removeImage(withIdentifier: "blue"), "重复移除应返回 false")
    XCTAssertNil(cache.image(withIdentifier: "blue"))
  }

  func testRemoveAllImages() {
    cache.add(TestSupport.makeSolidImage(color: .red), withIdentifier: "a")
    cache.add(TestSupport.makeSolidImage(color: .blue), withIdentifier: "b")

    let settle = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
    wait(for: [settle], timeout: 3.0)

    XCTAssertTrue(cache.removeAllImages())
    XCTAssertFalse(cache.removeAllImages(), "空缓存再次清空应返回 false")
    XCTAssertEqual(cache.memoryUsage, 0)
  }

  // MARK: - 内存计数

  func testMemoryUsageReflectsAddedImage() {
    // 32x32 @ scale 1,4 字节/像素 = 4096 字节
    let image = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 32, height: 32))
    cache.add(image, withIdentifier: "sized")

    let settle = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
    wait(for: [settle], timeout: 3.0)

    XCTAssertEqual(cache.memoryUsage, 4096)
  }

  func testDefaultCapacities() {
    XCTAssertEqual(cache.memoryCapacity, 100_000_000)
    XCTAssertEqual(cache.preferredMemoryUsage, 60_000_000)
  }
}
