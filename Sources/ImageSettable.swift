//
//  ImageSettable.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/1/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import UIKit

/// 可以把一张图片直接挂到 layer.contents 上的视图。
///
/// 走 layer 而非 UIImageView 的绘制路径,交由 GPU 合成。
@MainActor
public protocol ImageSettable: UIView {
  var backgroundImage: UIImage? { get set }
}

extension ImageSettable {
  /// 实现者应在 backgroundImage 的 didSet 中调用本方法。
  ///
  /// 1.x 在协议扩展里用 layer.contents 反推 UIImage,getter 里
  /// `obj as! CGImage` 会在 contents 非 CGImage 时崩溃,且往返会丢失
  /// scale 与 imageOrientation(B3)。2.0 起由实现者持有原始 UIImage。
  public func applyBackgroundImage(_ image: UIImage?) {
    layer.contents = image?.layerContents
    if image?.isOpaque == true {
      isOpaque = true
    } else {
      updateOpaque()
    }
  }
}

extension UIImage {
  /// 挂到 layer.contents 上的位图。
  ///
  /// layer.contents 只认 CGImage,而 CGImage 不携带 imageOrientation:方向不是 .up 的图
  /// (相机照片的 EXIF 方向就是这种)直接挂上去会旋转或镜像显示;CIImage 背书的图
  /// 更是连 cgImage 都没有,挂上去是一片空白。这两种图先按 UIKit 的绘制语义重绘成
  /// 一张正向位图 —— 只有它们付这一次重绘的代价,其余的照旧直接用 cgImage。
  fileprivate var layerContents: CGImage? {
    if imageOrientation == .up, let cgImage { return cgImage }
    guard size.width > 0, size.height > 0 else { return cgImage }
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      draw(at: .zero)
    }.cgImage
  }
}
