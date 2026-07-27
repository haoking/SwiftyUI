//
//  BackgroundImagable.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/1/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

/// 可以把一张图片直接挂到 layer.contents 上的视图。
///
/// 走 layer 而非 UIImageView 的绘制路径,交由 GPU 合成。
///
/// 本协议及其实现者(SwiftyButton、SwiftyImageView)有意**不**标注 @MainActor
/// —— 隔离标注在 Task 17 为全部 UI 类型统一添加,原因见 SwiftyLabel 中
/// "存储属性"一节的说明。
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
    layer.contents = image?.cgImage
    if image?.isOpaque == true {
      isOpaque = true
    } else {
      updateOpaque()
    }
  }
}
