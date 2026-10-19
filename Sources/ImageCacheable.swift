//
//  ImageCacheable.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/3/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import UIKit

/// 内存图片缓存的接口。
///
/// 1.x 曾用 associated object 在协议扩展中模拟存储属性,这既有 objc runtime
/// 开销,又在并发下必然丢更新(B4)。2.0 起协议只声明契约,存储由实现者提供。
public protocol ImageCacheable: AnyObject {
  /// 缓存上限。超过后触发淘汰。
  var memoryCapacity: UInt64 { get set }
  /// 淘汰后期望回落到的用量。
  var preferredMemoryUsage: UInt64 { get set }
  /// 当前用量。
  var memoryUsage: UInt64 { get }

  func add(_ image: UIImage, withIdentifier identifier: String)
  @discardableResult
  func removeImage(withIdentifier identifier: String) -> Bool
  @discardableResult
  func removeAllImages() -> Bool
  func image(withIdentifier identifier: String) -> UIImage?
}

/// ImageCachePool 的存储:字典 + 侵入式双向链表,命中、插入、淘汰都是 O(1)。
///
/// 2.x 每次超出容量都把全部条目按访问序号排一遍序(O(n log n),还要分配一个数组),
/// 而且是在锁里;缓存满载时每次 add 都会触发一次。这里节点放在一个连续数组里,
/// 前后指针是下标而不是对象引用:链表操作不产生引用计数流量,删掉的位置用空闲表复用。
///
/// 访问顺序就是链表顺序(头最旧、尾最新),不再需要访问序号;2.x 为避免时间戳打平
/// 而引入的那个严格递增计数器随之消失。
///
/// 不是线程安全的:ImageCachePool 只在自己的 Mutex 里访问它。
struct ImageLRU {
  private struct Node {
    var identifier: String
    /// 空闲节点置 nil,图片随删除立即释放,不必等到这个位置被复用。
    var image: UIImage?
    var cost: UInt64
    /// 更旧、更新的邻居在 nodes 里的下标;`ImageLRU.none` 表示没有。
    var older: Int
    var newer: Int
  }

  private static let none = -1

  private var nodes: [Node] = []
  private var freeSlots: [Int] = []
  private var slots: [String: Int] = [:]
  private var oldest = ImageLRU.none
  private var newest = ImageLRU.none

  private(set) var memoryUsage: UInt64 = 0

  var isEmpty: Bool { slots.isEmpty }

  /// 一张图解码后占用的字节数:按像素尺寸(点尺寸 × scale)、每像素 4 字节计算。
  static func cost(of image: UIImage) -> UInt64 {
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    return UInt64(width * 4) * UInt64(height)
  }

  /// 加入一张图并把它标为最新;标识已存在时替换原来的图。
  mutating func insert(_ image: UIImage, for identifier: String) {
    let cost = Self.cost(of: image)
    if let slot = slots[identifier] {
      // 1.x 直接做 UInt64 减法,计数一旦漂移就 trap(B5);这里保留钳制。
      memoryUsage = memoryUsage >= nodes[slot].cost ? memoryUsage - nodes[slot].cost : 0
      nodes[slot].image = image
      nodes[slot].cost = cost
      moveToNewest(slot)
    } else {
      let slot = allocate(
        Node(identifier: identifier, image: image, cost: cost, older: Self.none, newer: Self.none))
      slots[identifier] = slot
      linkAsNewest(slot)
    }
    memoryUsage += cost
  }

  /// 取出一张图;命中即标为最新。
  mutating func image(for identifier: String) -> UIImage? {
    guard let slot = slots[identifier] else { return nil }
    moveToNewest(slot)
    return nodes[slot].image
  }

  mutating func remove(_ identifier: String) -> Bool {
    guard let slot = slots.removeValue(forKey: identifier) else { return false }
    memoryUsage = memoryUsage >= nodes[slot].cost ? memoryUsage - nodes[slot].cost : 0
    unlink(slot)
    release(slot)
    return true
  }

  mutating func removeAll() {
    nodes.removeAll()
    freeSlots.removeAll()
    slots.removeAll()
    oldest = Self.none
    newest = Self.none
    memoryUsage = 0
  }

  /// 超出 capacity 时从最旧的开始删,直到删掉的字节数达到 memoryUsage − preferred。
  ///
  /// 逐字保留 2.x 的规则:先删再判断,所以只要超出容量就至少删一个;最新的条目在
  /// 必要时也会被删。preferred 可能被设得比 capacity 还大(两个 setter 互不校验),
  /// 此时目标钳到 0,不在这里 UInt64 下溢(B5)。
  mutating func purge(toFit capacity: UInt64, preferred: UInt64) {
    guard memoryUsage > capacity else { return }
    let bytesToPurge = memoryUsage >= preferred ? memoryUsage - preferred : 0

    var bytesPurged: UInt64 = 0
    while oldest != Self.none {
      let slot = oldest
      bytesPurged += nodes[slot].cost
      slots.removeValue(forKey: nodes[slot].identifier)
      unlink(slot)
      release(slot)
      if bytesPurged >= bytesToPurge { break }
    }
    memoryUsage = memoryUsage >= bytesPurged ? memoryUsage - bytesPurged : 0
  }

  // MARK: - 链表

  private mutating func allocate(_ node: Node) -> Int {
    if let slot = freeSlots.popLast() {
      nodes[slot] = node
      return slot
    }
    nodes.append(node)
    return nodes.count - 1
  }

  private mutating func release(_ slot: Int) {
    nodes[slot].image = nil
    nodes[slot].identifier = ""
    freeSlots.append(slot)
  }

  private mutating func unlink(_ slot: Int) {
    let older = nodes[slot].older
    let newer = nodes[slot].newer
    if older != Self.none { nodes[older].newer = newer } else { oldest = newer }
    if newer != Self.none { nodes[newer].older = older } else { newest = older }
    nodes[slot].older = Self.none
    nodes[slot].newer = Self.none
  }

  private mutating func linkAsNewest(_ slot: Int) {
    nodes[slot].older = newest
    nodes[slot].newer = Self.none
    if newest != Self.none { nodes[newest].newer = slot } else { oldest = slot }
    newest = slot
  }

  private mutating func moveToNewest(_ slot: Int) {
    guard slot != newest else { return }
    unlink(slot)
    linkAsNewest(slot)
  }
}
