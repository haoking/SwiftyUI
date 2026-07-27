//
//  SwiftyImage.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/1/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

//import CoreGraphics
import UIKit

extension UIImage {
  public final class func load(_ data: Data) -> UIImage? {
    return UIImage(data: data)
  }

  public final class func load(_ data: Data, scale: CGFloat) -> UIImage? {
    return UIImage(data: data, scale: scale)
  }

  public final class func load(_ name: String) -> UIImage? {
    // 真正需要保护的共享状态在 ImageCachePool 内部,由它自己加锁(见 Task 11)。
    let imageCachePool: ImageCachePool = .defalut
    if let cacheImage = imageCachePool.image(withIdentifier: name) {
      return cacheImage
    }
    guard let oriImage = UIImage(named: name) else { return nil }
    oriImage.inflate()
    imageCachePool.add(oriImage, withIdentifier: name)
    return oriImage
  }

  public final class func load(_ aImage: UIImage?, identifier: String) -> UIImage? {
    guard let oriImage = aImage else { return nil }
    let imageCachePool: ImageCachePool = .defalut
    oriImage.inflate()
    imageCachePool.add(oriImage, withIdentifier: identifier)
    return oriImage
  }
}

extension UIImage {
  private struct AssociatedKey {
    fileprivate static var isInflatedKey: UnsafeRawPointer = UnsafeRawPointer(
      UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
  }

  private final var isInflated: Bool {
    get {
      guard let obj = objc_getAssociatedObject(self, AssociatedKey.isInflatedKey) as? Bool else {

        self.isInflated = false
        return self.isInflated
      }
      return obj
    }
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

  public final var isOpaque: Bool {

    let alphaInfo = cgImage?.alphaInfo
    return
      !(alphaInfo == .first || alphaInfo == .last || alphaInfo == .premultipliedFirst
      || alphaInfo == .premultipliedLast)
  }

  public final func reSize(to size: CGSize) -> UIImage {
    guard size.width > 0 && size.height > 0 else { return self }

    UIGraphicsBeginImageContextWithOptions(size, isOpaque, 0.0)
    draw(in: CGRect(origin: .zero, size: size))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext() ?? self
    UIGraphicsEndImageContext()

    return scaledImage
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

    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    draw(in: CGRect(origin: origin, size: scaledSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext() ?? self
    UIGraphicsEndImageContext()

    return scaledImage
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

    UIGraphicsBeginImageContextWithOptions(size, isOpaque, 0.0)
    draw(in: CGRect(origin: origin, size: scaledSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext() ?? self
    UIGraphicsEndImageContext()

    return scaledImage
  }

  public final func rounded(
    withCornerRadius radius: CGFloat, divideRadiusByImageScale: Bool = false
  ) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)

    let scaledRadius = divideRadiusByImageScale ? radius / scale : radius

    let clippingPath = UIBezierPath(
      roundedRect: CGRect(origin: CGPoint.zero, size: size), cornerRadius: scaledRadius)
    clippingPath.addClip()

    draw(in: CGRect(origin: CGPoint.zero, size: size))

    let roundedImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()

    return roundedImage
  }

  public final func roundedIntoCircle() -> UIImage {
    let radius = min(size.width, size.height) / 2.0
    var squareImage = self
    if size.width != size.height {
      let squareDimension = min(size.width, size.height)
      let squareSize = CGSize(width: squareDimension, height: squareDimension)
      squareImage = reSize(toFill: squareSize)
    }

    UIGraphicsBeginImageContextWithOptions(squareImage.size, false, 0.0)
    let clippingPath = UIBezierPath(
      roundedRect: CGRect(origin: CGPoint.zero, size: squareImage.size), cornerRadius: radius)
    clippingPath.addClip()
    squareImage.draw(in: CGRect(origin: CGPoint.zero, size: squareImage.size))
    let roundedImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()

    return roundedImage
  }
}

public final class ImageCachePool: ImageCacheable {
  public static let `defalut`: ImageCachePool = {
    return ImageCachePool()
  }()

  // block 形式注册的观察者由返回的 token 代表,removeObserver(self) 不生效(B18)
  private var memoryWarningObserver: (any NSObjectProtocol)?

  // internal 以便单元测试构造独立实例。对外仍只暴露静态单例访问器。
  init() {
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
    ) { [weak self] (_) in

      guard let strongSelf = self else { return }
      strongSelf.removeAllImages()
    }
  }

  deinit {
    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
