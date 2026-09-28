//
//  SwiftyImage.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/1/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

extension UIImage {
  public final class func load(_ data: Data) -> UIImage? {
    return UIImage(data: data)
  }

  public final class func load(_ data: Data, scale: CGFloat) -> UIImage? {
    return UIImage(data: data, scale: scale)
  }

  public final class func load(_ name: String) -> UIImage? {
    // 真正需要保护的共享状态在 ImageCachePool 内部,由它自己加锁(见 docs/superpowers/plans/2026-07-27-swiftyui-2.0-modernization.md 的 Task 11)。
    let imageCachePool: ImageCachePool = .default
    if let cacheImage = imageCachePool.image(withIdentifier: name) {
      return cacheImage
    }
    guard let oriImage = UIImage(named: name) else { return nil }
    // 缓存一张已经解码好的副本:preparingForDisplay()(iOS 15+)返回绘制时无需再解码
    // 的新图,比 inflate() 那种"把数据读一遍再丢掉"更可靠。图片是这里现建的,调用方
    // 手里没有原对象,换成副本不影响任何人。拿不到副本时退回 inflate()。
    let image: UIImage
    if let decoded = oriImage.preparingForDisplay() {
      decoded.isInflated = true
      image = decoded
    } else {
      oriImage.inflate()
      image = oriImage
    }
    imageCachePool.add(image, withIdentifier: name)
    return image
  }

  public final class func load(_ aImage: UIImage?, identifier: String) -> UIImage? {
    guard let oriImage = aImage else { return nil }
    let imageCachePool: ImageCachePool = .default
    oriImage.inflate()
    imageCachePool.add(oriImage, withIdentifier: identifier)
    return oriImage
  }
}

extension UIImage {
  private struct AssociatedKey {
    // 全库唯一保留 associated object 的地方:UIImage 是外部类型,无法为它
    // 添加存储属性。key 本身只是一个进程内稳定的地址,分配后再不写入、
    // 不承载任何可变状态,故 nonisolated(unsafe) 在此是安全的。
    nonisolated(unsafe) fileprivate static let isInflatedKey = UnsafeRawPointer(
      UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
  }

  private final var isInflated: Bool {
    // 读不到就是没 inflate 过。曾经在这里先写入 false 再读第二遍 —— getter 带副作用。
    get { (objc_getAssociatedObject(self, AssociatedKey.isInflatedKey) as? Bool) ?? false }
    set {
      objc_setAssociatedObject(
        self, AssociatedKey.isInflatedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  public final func inflate() {
    guard !isInflated else { return }
    isInflated = true
    _ = cgImage?.dataProvider?.data
  }

  /// 只有确知没有 alpha 通道时才返回 true。
  ///
  /// 没有 CGImage(CIImage 背书)时 alpha 无从得知,按不透明处理会让 reSize 开不透明
  /// 上下文、把透明区涂黑,故保守地返回 false;`.alphaOnly` 只有 alpha 通道,同样不是
  /// 不透明的。原实现只排除四种带 alpha 的取值,这两种情形都落成了 true。
  public final var isOpaque: Bool {
    switch cgImage?.alphaInfo {
    case .none?, .noneSkipFirst?, .noneSkipLast?:
      return true
    default:
      return false
    }
  }

  public final func reSize(to size: CGSize) -> UIImage {
    guard size.width > 0 && size.height > 0 else { return self }

    return Self.render(size: size, opaque: isOpaque) {
      draw(in: CGRect(origin: .zero, size: size))
    }
  }

  public final func reSize(toFit size: CGSize) -> UIImage {
    guard size.width > 0 && size.height > 0 else { return self }

    let imageAspectRatio = self.size.width / self.size.height
    let canvasAspectRatio = size.width / size.height
    var resizeFactor: CGFloat
    if imageAspectRatio > canvasAspectRatio {
      resizeFactor = size.width / self.size.width
    } else {
      resizeFactor = size.height / self.size.height
    }
    let scaledSize = CGSize(
      width: self.size.width * resizeFactor, height: self.size.height * resizeFactor)
    let origin = CGPoint(
      x: (size.width - scaledSize.width) / 2.0, y: (size.height - scaledSize.height) / 2.0)

    return Self.render(size: size, opaque: false) {
      draw(in: CGRect(origin: origin, size: scaledSize))
    }
  }

  public final func reSize(toFill size: CGSize) -> UIImage {
    guard size.width > 0 && size.height > 0 else { return self }

    let imageAspectRatio = self.size.width / self.size.height
    let canvasAspectRatio = size.width / size.height
    var resizeFactor: CGFloat
    if imageAspectRatio > canvasAspectRatio {
      resizeFactor = size.height / self.size.height
    } else {
      resizeFactor = size.width / self.size.width
    }
    let scaledSize = CGSize(
      width: self.size.width * resizeFactor, height: self.size.height * resizeFactor)
    let origin = CGPoint(
      x: (size.width - scaledSize.width) / 2.0, y: (size.height - scaledSize.height) / 2.0)

    return Self.render(size: size, opaque: isOpaque) {
      draw(in: CGRect(origin: origin, size: scaledSize))
    }
  }

  public final func rounded(
    withCornerRadius radius: CGFloat, divideRadiusByImageScale: Bool = false
  ) -> UIImage {
    // 与上面三个 reSize 方法同一条守卫:尺寸为零时没有位图可画,原样返回。
    // (这里曾对 UIGraphicsGetImageFromCurrentImageContext() 强解包,零尺寸时
    // 根本不会有 context,`UIImage().rounded(withCornerRadius: 5)` 直接 trap。)
    guard size.width > 0 && size.height > 0 else { return self }

    let scaledRadius = divideRadiusByImageScale ? radius / scale : radius
    return Self.render(size: size, opaque: false) {
      UIBezierPath(
        roundedRect: CGRect(origin: CGPoint.zero, size: size), cornerRadius: scaledRadius
      ).addClip()
      draw(in: CGRect(origin: CGPoint.zero, size: size))
    }
  }

  public final func roundedIntoCircle() -> UIImage {
    // 同 rounded(withCornerRadius:):零尺寸时原样返回
    guard size.width > 0 && size.height > 0 else { return self }

    let radius = min(size.width, size.height) / 2.0
    var squareImage = self
    if size.width != size.height {
      let squareDimension = min(size.width, size.height)
      let squareSize = CGSize(width: squareDimension, height: squareDimension)
      squareImage = reSize(toFill: squareSize)
    }

    return Self.render(size: squareImage.size, opaque: false) {
      UIBezierPath(
        roundedRect: CGRect(origin: CGPoint.zero, size: squareImage.size), cornerRadius: radius
      ).addClip()
      squareImage.draw(in: CGRect(origin: CGPoint.zero, size: squareImage.size))
    }
  }

  /// 按屏幕 scale(等同于 UIGraphicsBeginImageContextWithOptions 传 0)、标准色域出一张图,
  /// drawing 在 UIKit 的当前上下文里执行。库里的绘图都走这里(SwiftyAlertIcons 也用)。
  static func render(size: CGSize, opaque: Bool, _ drawing: () -> Void) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = opaque
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in drawing() }
  }
}

public final class ImageCachePool: ImageCacheable, @unchecked Sendable {
  public static let `default`: ImageCachePool = {
    return ImageCachePool()
  }()

  @available(
    *, deprecated, renamed: "default",
    message: "拼写错误,2.0 起改为 default。旧名将在下个大版本移除。"
  )
  public static var defalut: ImageCachePool { `default` }

  // 一把锁保护下面全部状态。缓存操作的临界区都很短,
  // 比 1.x 的并发队列 + barrier/sync 混用既更快也更正确(B4/B5)。
  private let lock = NSLock()
  private var cachedImages: [String: CachedImage] = [:]
  private var currentMemoryUsage: UInt64 = 0
  private var _memoryCapacity: UInt64 = 100_000_000
  private var _preferredMemoryUsage: UInt64 = 60_000_000
  // CachedImage.lastAccessSequence 的发号器,同样只在持锁状态下读写。
  private var accessSequenceCounter: UInt64 = 0

  // block 形式注册的观察者由返回的 token 代表,removeObserver(self) 不生效(B18)
  private var memoryWarningObserver: (any NSObjectProtocol)?

  // internal 以便单元测试构造独立实例。对外仍只暴露静态单例访问器。
  init() {
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.removeAllImages()
    }
  }

  deinit {
    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - 容量

  public var memoryCapacity: UInt64 {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _memoryCapacity
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _memoryCapacity = newValue
    }
  }

  public var preferredMemoryUsage: UInt64 {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _preferredMemoryUsage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _preferredMemoryUsage = newValue
    }
  }

  public var memoryUsage: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return currentMemoryUsage
  }

  // MARK: - 存取

  /// 加入缓存。
  ///
  /// 1.x 用两个异步 barrier 块完成,调用方无法知道何时落地。
  /// 2.0 起同步完成,行为可预测。
  public func add(_ image: UIImage, withIdentifier identifier: String) {
    lock.lock()
    defer { lock.unlock() }

    let cachedImage = CachedImage(image, identifier: identifier)
    if let previous = cachedImages[identifier] {
      currentMemoryUsage =
        currentMemoryUsage >= previous.totalBytes
        ? currentMemoryUsage - previous.totalBytes
        : 0
    }
    accessSequenceCounter += 1
    cachedImage.lastAccessSequence = accessSequenceCounter
    cachedImages[identifier] = cachedImage
    currentMemoryUsage += cachedImage.totalBytes

    purgeIfNeededLocked()
  }

  @discardableResult
  public func removeImage(withIdentifier identifier: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    guard let cachedImage = cachedImages.removeValue(forKey: identifier) else { return false }
    // 1.x 直接做 UInt64 减法,计数一旦漂移就 trap(B5)
    currentMemoryUsage =
      currentMemoryUsage >= cachedImage.totalBytes
      ? currentMemoryUsage - cachedImage.totalBytes
      : 0
    return true
  }

  @discardableResult
  public func removeAllImages() -> Bool {
    lock.lock()
    defer { lock.unlock() }

    guard !cachedImages.isEmpty else { return false }
    cachedImages.removeAll()
    currentMemoryUsage = 0
    return true
  }

  public func image(withIdentifier identifier: String) -> UIImage? {
    lock.lock()
    defer { lock.unlock() }

    guard let cachedImage = cachedImages[identifier] else { return nil }
    accessSequenceCounter += 1
    cachedImage.lastAccessSequence = accessSequenceCounter
    return cachedImage.image
  }

  // MARK: - 淘汰

  /// 调用方必须已持有 lock。
  private func purgeIfNeededLocked() {
    guard currentMemoryUsage > _memoryCapacity else { return }

    // 钳住下限:preferredMemoryUsage 可能被调用方设得比 memoryCapacity 还大
    // (两个 setter 互不校验),此时 currentMemoryUsage 可能高于 capacity(触发
    // 淘汰)却低于 preferred,不钳制就会在这里 UInt64 下溢 trap(B5)。
    let bytesToPurge =
      currentMemoryUsage >= _preferredMemoryUsage
      ? currentMemoryUsage - _preferredMemoryUsage
      : 0
    // 按访问序号升序:最久未访问的排在最前,优先淘汰。
    // 用严格单调的整数序号而不是时间戳排序,见 CachedImage.lastAccessSequence 的说明。
    let sorted = cachedImages.values.sorted { $0.lastAccessSequence < $1.lastAccessSequence }

    var bytesPurged: UInt64 = 0
    for cachedImage in sorted {
      cachedImages.removeValue(forKey: cachedImage.identifier)
      bytesPurged += cachedImage.totalBytes
      if bytesPurged >= bytesToPurge { break }
    }

    currentMemoryUsage =
      currentMemoryUsage >= bytesPurged
      ? currentMemoryUsage - bytesPurged
      : 0
  }
}
