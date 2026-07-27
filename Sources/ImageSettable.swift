//
//  BackgroundImagable.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/1/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public protocol ImageSettable: AnyObject {
  var backgroundImage: UIImage? { get set }
}

extension ImageSettable where Self: UIView {
  public var backgroundImage: UIImage? {
    get {
      guard let obj = layer.contents else { return nil }
      return UIImage(cgImage: obj as! CGImage)
    }
    set {
      layer.contents = newValue?.cgImage
      if newValue?.isOpaque == true {
        isOpaque = true
      } else {
        updateOpaque()
      }
    }
  }
}
