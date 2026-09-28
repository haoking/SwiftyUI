//
//  ImageCacheable.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/3/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

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

/// 缓存条目。
final class CachedImage {
  let image: UIImage
  let identifier: String
  let totalBytes: UInt64
  /// 淘汰排序的判据(最久未访问的先淘汰),由 ImageCachePool 在持锁状态下赋值、严格单调递增。
  ///
  /// 曾经按最后访问的 Date 排序,但同一临界区内连续几次操作可能跑得
  /// 比时钟采样精度还快、拿到完全相同的 Date——实测中不仅 Date(),连
  /// DispatchTime 的纳秒级单调时钟在这种连续调用下也会撞到相同读数。
  /// 时间戳一旦打平,sorted(by:) 对并列项的相对顺序就退化成字典哈希遍历
  /// 顺序(逐进程随机),淘汰结果因此不确定。这个整数序号在锁内每次
  /// 加一,不依赖任何时钟,天然不会打平,用它做排序判据即可保证确定性。
  var lastAccessSequence: UInt64 = 0

  init(_ image: UIImage, identifier: String) {
    self.image = image
    self.identifier = identifier
    let size = CGSize(
      width: image.size.width * image.scale,
      height: image.size.height * image.scale)
    let bytesPerPixel: CGFloat = 4.0
    let bytesPerRow = size.width * bytesPerPixel
    self.totalBytes = UInt64(bytesPerRow) * UInt64(size.height)
  }
}
