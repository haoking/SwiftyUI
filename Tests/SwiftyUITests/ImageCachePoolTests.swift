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

    // 取出局部引用后再进并发块:XCTestCase 自身不是 Sendable,捕获 self
    // 会被严格并发检查拒绝;ImageCachePool 是 Sendable,可直接捕获。
    let cache = self.cache!
    DispatchQueue.concurrentPerform(iterations: 200) { index in
      let key = "concurrent-\(index % 20)"
      if index % 3 == 0 {
        cache.removeImage(withIdentifier: key)
      } else {
        cache.add(image, withIdentifier: key)
      }
      _ = cache.image(withIdentifier: key)
    }

    // 遍历全部可能的 key,独立数出实际驻留的条目数,
    // 再据此校验内存计数。这个不变量在任何正确实现下都成立
    // (与哪个并发写入者"胜出"无关),而丢更新会直接破坏它。
    // 原来的 usage % perImageBytes == 0 是结构性无效的:
    // 每张图都是 256 字节,丢一次更新只会让计数偏移 256 的整数倍。
    var liveCount = 0
    for index in 0..<20 {
      if cache.image(withIdentifier: "concurrent-\(index)") != nil {
        liveCount += 1
      }
    }
    XCTAssertEqual(
      cache.memoryUsage, UInt64(liveCount) * perImageBytes,
      "内存计数与实际驻留条目数不符,说明存在丢更新(B4)")
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

  /// B5:两个容量设反时不应 trap。
  /// preferredMemoryUsage > memoryCapacity 是易犯的配置错误,
  /// 此时 currentMemoryUsage 可能高于 capacity(触发淘汰)却低于 preferred,
  /// 未钳制的减法会在这里下溢。
  func testInvertedCapacitiesDoNotUnderflow() {
    cache.memoryCapacity = 256 * 2
    cache.preferredMemoryUsage = 256 * 10  // 故意大于 capacity

    let image = TestSupport.makeSolidImage(color: .red, size: CGSize(width: 8, height: 8))
    for index in 0..<5 {
      cache.add(image, withIdentifier: "inverted-\(index)")
    }
    // 能走到这里就说明没有 trap
    XCTAssertLessThanOrEqual(cache.memoryUsage, 256 * 5)
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

// MARK: - 与 2.1.0 淘汰算法对拍

extension ImageCachePoolTests {

  /// 随机增、删、读、清空、改容量 5000 步,每一步都与 2.1.0 的排序式 LRU 逐项比对。
  ///
  /// 3.0 把淘汰从"每次超出容量就按访问序号全排序"换成了 O(1) 的链表,淘汰顺序与
  /// 内存计数必须与旧算法完全一致。只走公开 API:读操作本身就是序列的一部分
  /// (它会刷新新旧顺序,对两边一视同仁),淘汰错一个,之后读到它时就会对不上;
  /// 结尾再把全部标识读一遍。
  ///
  /// 判别力:把新实现的淘汰改成从最新的删、或去掉命中时的"移到最新",本测试变红。
  func testLRUMatchesReferenceModelUnderRandomOperations() {
    var rng = SplitMix64(seed: 0x5157_4654_5955_4931)
    let identifiers = (0..<10).map { "lru-\($0)" }
    // 每种尺寸两张不同的图:读操作比对的是对象身份,同尺寸也分得出是哪一张。
    let images = [4, 8, 16, 32].flatMap { side in
      [UIColor.red, .blue].map {
        TestSupport.makeSolidImage(color: $0, size: CGSize(width: side, height: side))
      }
    }
    let capacities: [UInt64] = [0, 256, 1024, 2048, 4096, 8192, 16384, 100_000_000]

    let cache = ImageCachePool()
    var reference = ReferenceLRU()

    for step in 0..<5000 {
      let identifier = identifiers[Int(rng.next() % UInt64(identifiers.count))]
      switch rng.next() % 100 {
      case 0..<40:
        let image = images[Int(rng.next() % UInt64(images.count))]
        cache.add(image, withIdentifier: identifier)
        reference.add(image, identifier)
      case 40..<70:
        XCTAssertTrue(
          cache.image(withIdentifier: identifier) === reference.image(identifier),
          "第 \(step) 步:读 \(identifier) 的结果不一致")
      case 70..<85:
        XCTAssertEqual(
          cache.removeImage(withIdentifier: identifier), reference.remove(identifier),
          "第 \(step) 步:remove 的返回值不一致")
      case 85..<87:
        XCTAssertEqual(
          cache.removeAllImages(), reference.removeAll(), "第 \(step) 步:removeAll 的返回值不一致")
      case 87..<95:
        let capacity = capacities[Int(rng.next() % UInt64(capacities.count))]
        cache.memoryCapacity = capacity
        reference.capacity = capacity
      default:
        let preferred = capacities[Int(rng.next() % UInt64(capacities.count))]
        cache.preferredMemoryUsage = preferred
        reference.preferred = preferred
      }
      XCTAssertEqual(cache.memoryUsage, reference.usage, "第 \(step) 步:内存计数不一致")
    }

    for identifier in identifiers {
      XCTAssertTrue(
        cache.image(withIdentifier: identifier) === reference.image(identifier),
        "结束时 \(identifier) 的驻留情况不一致")
    }
  }
}

/// 2.1.0 的 ImageCachePool 淘汰算法,原样搬来做参照:字典 + 严格递增的访问序号,
/// 超出容量时按序号全排序,从最旧的开始删。
private struct ReferenceLRU {
  struct Entry {
    let image: UIImage
    let cost: UInt64
    var sequence: UInt64
  }

  var entries: [String: Entry] = [:]
  var usage: UInt64 = 0
  var capacity: UInt64 = 100_000_000
  var preferred: UInt64 = 60_000_000
  var counter: UInt64 = 0

  static func cost(of image: UIImage) -> UInt64 {
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    return UInt64(width * 4) * UInt64(height)
  }

  mutating func add(_ image: UIImage, _ identifier: String) {
    if let previous = entries[identifier] {
      usage = usage >= previous.cost ? usage - previous.cost : 0
    }
    counter += 1
    let cost = Self.cost(of: image)
    entries[identifier] = Entry(image: image, cost: cost, sequence: counter)
    usage += cost
    purgeIfNeeded()
  }

  mutating func image(_ identifier: String) -> UIImage? {
    guard var entry = entries[identifier] else { return nil }
    counter += 1
    entry.sequence = counter
    entries[identifier] = entry
    return entry.image
  }

  mutating func remove(_ identifier: String) -> Bool {
    guard let entry = entries.removeValue(forKey: identifier) else { return false }
    usage = usage >= entry.cost ? usage - entry.cost : 0
    return true
  }

  mutating func removeAll() -> Bool {
    guard !entries.isEmpty else { return false }
    entries.removeAll()
    usage = 0
    return true
  }

  private mutating func purgeIfNeeded() {
    guard usage > capacity else { return }
    let toPurge = usage >= preferred ? usage - preferred : 0
    var purged: UInt64 = 0
    for (identifier, entry) in entries.sorted(by: { $0.value.sequence < $1.value.sequence }) {
      entries.removeValue(forKey: identifier)
      purged += entry.cost
      if purged >= toPurge { break }
    }
    usage = usage >= purged ? usage - purged : 0
  }
}

/// 固定种子的随机数发生器:对拍序列每次运行都相同,失败可以复现。
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
