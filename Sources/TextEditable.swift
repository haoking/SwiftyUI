//
//  TextEditable.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/30/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

/// 文本在视图中的对齐方式。
public enum TextContentAlignment: Int {
  case center
  case top
  case bottom
  case left
  case right
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight

  /// 计算文本容器在视图内的绘制原点。
  func alignOffset(viewSize: CGSize, containerSize: CGSize) -> CGPoint {
    let xMargin = viewSize.width - containerSize.width
    let yMargin = viewSize.height - containerSize.height

    switch self {
    case .center:
      return CGPoint(x: max(xMargin / 2, 0), y: max(yMargin / 2, 0))
    case .top:
      return CGPoint(x: max(xMargin / 2, 0), y: 0)
    case .bottom:
      return CGPoint(x: max(xMargin / 2, 0), y: max(yMargin, 0))
    case .left:
      return CGPoint(x: 0, y: max(yMargin / 2, 0))
    case .right:
      return CGPoint(x: max(xMargin, 0), y: max(yMargin / 2, 0))
    case .topLeft:
      return CGPoint(x: 0, y: 0)
    case .topRight:
      return CGPoint(x: max(xMargin, 0), y: 0)
    case .bottomLeft:
      return CGPoint(x: 0, y: max(yMargin, 0))
    case .bottomRight:
      return CGPoint(x: max(xMargin, 0), y: max(yMargin, 0))
    }
  }
}

/// 用 TextKit 自绘文本的视图所提供的能力。
///
/// 1.x 曾用 9 个 associated object 在协议扩展中模拟存储属性,而实现者只有
/// SwiftyLabel 一个。2.0 起协议只声明契约,存储由实现者以真实属性提供。
///
/// 本协议有意**不**标注 @MainActor —— 隔离标注在 Task 17 统一添加,
/// 原因见 SwiftyLabel 中"存储属性"一节的说明。
public protocol TextEditable: UIView {
  var usesIntrinsicContentSize: Bool { get set }
  var textAlignment: TextContentAlignment { get set }
  var font: UIFont { get set }
  var textColor: UIColor { get set }
  var paragraphStyle: NSParagraphStyle { get set }
  var numberOfLines: Int { get set }
  var padding: CGFloat { get set }
  var lineBreakMode: NSLineBreakMode { get set }
  var text: String? { get set }
  var shadow: NSShadow? { get set }
  var attributedText: NSAttributedString? { get set }
}
