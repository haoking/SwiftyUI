//
//  SwiftyGlobal.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/28/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

/// 全局 UI 度量。
///
/// 全部为实时计算属性:旋转、分屏、多窗口下都会取到当前值。
/// 1.x 曾用 static var 一次性缓存,那在上述场景下必然失效(B17)。
@MainActor
public enum SwiftyGlobal {
  /// 当前处于前台活跃状态的 window scene 的 key window。
  ///
  /// 1.x 返回非可选并强解包 `UIApplication.shared.keyWindow!`,无窗口时崩溃(B1)。
  /// 2.0 起返回可选,调用方需自行处理 nil。
  public static var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .keyWindow
  }

  public static var screenSize: CGSize { keyWindow?.bounds.size ?? .zero }

  public static var screenWidth: CGFloat { screenSize.width }

  public static var screenHeight: CGFloat { screenSize.height }

  public static var statusHeight: CGFloat {
    keyWindow?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
  }

  /// key window 的安全区内边距。
  ///
  /// 2.0 新增,用于替代已删除的 `navHeight` / `barHeight`——
  /// 后者用一个临时 UINavigationController 求默认高度,与调用方实际使用的
  /// 导航栏无关,且随横竖屏变化,本身就是错的(B2)。
  public static var safeAreaInsets: UIEdgeInsets { keyWindow?.safeAreaInsets ?? .zero }

  /// 设备型号名。未知型号返回原始 identifier。
  public nonisolated static let modelName: String = {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else { return identifier }
      return identifier + String(UnicodeScalar(UInt8(value)))
    }

    switch identifier {
    case "i386", "x86_64", "arm64": return "Simulator"
    default: return identifier
    }
  }()
}

public final class ClosureVoidWrapper {
  public var closure: (() -> Void)?

  public init(_ closure: (() -> Void)?) {
    self.closure = closure
  }
}

public final class ClosureWrapper<T> {
  public var closure: ((_ obj: T?) -> Void)?

  public init(_ closure: ((_ obj: T?) -> Void)?) {
    self.closure = closure
  }
}

extension NSObject {
  /// 交换实例方法实现。属于库的实现细节,2.0 起不再公开(仅供
  /// SwiftyUI.enableGlobalOpaqueOptimization() 内部调用)。
  final class func swizzleInstance(
    _ originalSelector: Selector, _ swizzledSelector: Selector
  ) {
    guard let originalMethod = class_getInstanceMethod(self, originalSelector),
      let swizzledMethod = class_getInstanceMethod(self, swizzledSelector)
    else { return }

    let isAddMethod: Bool = class_addMethod(
      self, originalSelector, method_getImplementation(swizzledMethod),
      method_getTypeEncoding(swizzledMethod))
    if isAddMethod {
      class_replaceMethod(
        self, swizzledSelector, method_getImplementation(originalMethod),
        method_getTypeEncoding(originalMethod))
    } else {
      method_exchangeImplementations(originalMethod, swizzledMethod)
    }
  }

  /// 交换类方法实现。同上,2.0 起不再公开。
  ///
  /// 当前仓库内已无调用方(SwiftyButton 的 swizzle 已在 Task 14 移除)。
  /// 是否继续保留交由最终审查裁定 —— 未删除,仅收紧可见性。
  final class func swizzleStatic(_ originalSelector: Selector, _ swizzledSelector: Selector) {
    guard let swizzledClass = object_getClass(self),
      let originalMethod = class_getClassMethod(swizzledClass, originalSelector),
      let swizzledMethod = class_getClassMethod(swizzledClass, swizzledSelector)
    else { return }

    let isAddMethod: Bool = class_addMethod(
      swizzledClass, originalSelector, method_getImplementation(swizzledMethod),
      method_getTypeEncoding(swizzledMethod))
    if isAddMethod {
      class_replaceMethod(
        swizzledClass, swizzledSelector, method_getImplementation(originalMethod),
        method_getTypeEncoding(originalMethod))
    } else {
      method_exchangeImplementations(originalMethod, swizzledMethod)
    }
  }
}
