//
//  SwiftyGlobal.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 9/28/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import UIKit

// SPM 使用者会先被 Package.swift 的 swift-tools-version 6.2 挡住,并看到一条清楚的提示;
// CocoaPods 没有 manifest 这一关,旧编译器只会在 `nonisolated(nonsending)` 之类的新语法上
// 报出一串难懂的语法错误。这里给他们同样清楚的一句话。
#if !compiler(>=6.2)
  #error("SwiftyUI 3.0 需要 Swift 6.2 编译器(Xcode 26.0 或更新)")
#endif

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
    // 直接遍历,不先 compactMap 出一个中间数组;screenSize 等派生度量每次都要走这里。
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
    where scene.activationState == .foregroundActive {
      return scene.keyWindow
    }
    return nil
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

  /// 设备型号标识符,即 `uname` 的 machine 字段(如 `"iPhone17,1"`);模拟器返回 `"Simulator"`。
  ///
  /// 不做任何"标识符 → 可读名称"的映射:1.x 的映射表已在 2.0 删除,真机一律返回原始标识符。
  public nonisolated static let modelName: String = {
    var systemInfo = utsname()
    uname(&systemInfo)
    // machine 是定长的 CChar 元组,按字节解码到第一个 0 为止。曾用 Mirror 反射
    // 这个 256 元素的元组,逐个元素拼字符串。
    let identifier = withUnsafeBytes(of: systemInfo.machine) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    switch identifier {
    case "i386", "x86_64", "arm64": return "Simulator"
    default: return identifier
    }
  }()
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
}
