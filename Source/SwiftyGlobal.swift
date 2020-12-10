//
//  SwiftyGlobal.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/28/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public final class SwiftyGlobal
{
    private(set) static var screenSize : CGSize = UIScreen.main.bounds.size
    private(set) static var screenWidth : CGFloat = screenSize.width
    private(set) static var screenHeight : CGFloat = screenSize.height
    
    private(set) static var statusHeight : CGFloat = UIApplication.shared.statusBarFrame.size.height
    private(set) static var navHeight : CGFloat = UINavigationController().navigationBar.frame.size.height
    private(set) static var barHeight : CGFloat = statusHeight + navHeight
    
    private(set) static var keyWindow : UIWindow = UIApplication.shared.keyWindow!
    
    //internal static let modelName: String = {
    private(set) static var modelName: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        switch identifier {
        case "iPod5,1":                                 return "iPod Touch 5"
        case "iPod7,1":                                 return "iPod Touch 6"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3":     return "iPhone 4"
        case "iPhone4,1":                               return "iPhone 4s"
        case "iPhone5,1", "iPhone5,2":                  return "iPhone 5"
        case "iPhone5,3", "iPhone5,4":                  return "iPhone 5c"
        case "iPhone6,1", "iPhone6,2":                  return "iPhone 5s"
        case "iPhone7,2":                               return "iPhone 6"
        case "iPhone7,1":                               return "iPhone 6 Plus"
        case "iPhone8,1":                               return "iPhone 6s"
        case "iPhone8,2":                               return "iPhone 6s Plus"
        case "iPhone9,1", "iPhone9,3":                  return "iPhone 7"
        case "iPhone9,2", "iPhone9,4":                  return "iPhone 7 Plus"
        case "iPhone8,4":                               return "iPhone SE"
        case "iPhone10,1", "iPhone10,4":                return "iPhone 8"
        case "iPhone10,2", "iPhone10,5":                return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6":                return "iPhone X"
        case "iPhone11,2":                              return "iPhone XS"
        case "iPhone11,4", "iPhone11,6":                return "iPhone XS MAX"
        case "iPhone11,8":                              return "iPhone XR"
        case "iPhone12,1":                              return "iPhone 11"
        case "iPhone12,3":                              return "iPhone 11 Pro"
        case "iPhone12,5":                              return "iPhone 11 Pro Max"
        case "iPhone12,8":                              return "iPhone SE (2nd generation)"
        case "iPhone13,1":                              return "iPhone 12 mini"
        case "iPhone13,2":                              return "iPhone 12"
        case "iPhone13,3":                              return "iPhone 12 Pro"
        case "iPhone13,4":                              return "iPhone 12 Pro Max"
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4":return "iPad 2"
        case "iPad3,1", "iPad3,2", "iPad3,3":           return "iPad (3rd generation)"
        case "iPad3,4", "iPad3,5", "iPad3,6":           return "iPad (4th generation)"
        case "iPad6,11", "iPad6,12":                    return "iPad (5th generation)"
        case "iPad7,5", "iPad7,6":                      return "iPad (6th generation)"
        case "iPad7,11", "iPad7,12":                    return "iPad (7th generation)"
        case "iPad4,1", "iPad4,2", "iPad4,3":           return "iPad Air"
        case "iPad5,3", "iPad5,4":                      return "iPad Air 2"
        case "iPad11,4", "iPad11,5":                    return "iPad Air (3rd generation)"
        case "iPad2,5", "iPad2,6", "iPad2,7":           return "iPad mini"
        case "iPad4,4", "iPad4,5", "iPad4,6":           return "iPad mini 2"
        case "iPad4,7", "iPad4,8", "iPad4,9":           return "iPad mini 3"
        case "iPad5,1", "iPad5,2":                      return "iPad mini 4"
        case "iPad11,1", "iPad11,2":                    return "iPad mini (5th generation)"
        case "iPad6,3", "iPad6,4":                      return "iPad Pro (9.7-inch)"
        case "iPad7,3", "iPad7,4":                      return "iPad Pro (10.5-inch)"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4":return "iPad Pro (11-inch)"
        case "iPad8,9", "iPad8,10":                     return "iPad Pro (11-inch) (2nd generation)"
        case "iPad6,7", "iPad6,8":                      return "iPad Pro (12.9-inch)"
        case "iPad7,1", "iPad7,2":                      return "iPad Pro (12.9-inch) (2nd generation)"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8":return "iPad Pro (12.9-inch) (3rd generation)"
        case "iPad8,11", "iPad8,12":                    return "iPad Pro (12.9-inch) (4th generation)"
        case "AppleTV5,3":                              return "Apple TV"
        case "AppleTV6,2":                              return "Apple TV 4K"
        case "AudioAccessory1,1":                       return "HomePod"
        case "i386", "x86_64":                          return "Simulator"
        default:                                        return identifier
        }
    }()
}

public final class ClosureVoidWrapper
{
    public var closure: (() -> Void)?
    
    public init(_ closure: (() -> Void)?) {
        self.closure = closure
    }
}

public final class ClosureWrapper<T>
{
    public var closure: ((_ obj: T?) -> Void)?
    
    public init(_ closure: ((_ obj: T?) -> Void)?) {
        self.closure = closure
    }
}

//extension NotificationCenter
//{
//    private struct SwiftyNotificationCenterAssociatedKeys {
//        fileprivate static var selectorBlockKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
//    }
//
//    private final var selectorWrapper : ClosureWrapper<Notification>? {
//        get {
//            guard let wrapper = objc_getAssociatedObject(self, SwiftyNotificationCenterAssociatedKeys.selectorBlockKey) as? ClosureWrapper<Notification> else { return nil }
//            return wrapper
//        }
//        set {
//            objc_setAssociatedObject(self, SwiftyNotificationCenterAssociatedKeys.selectorBlockKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
//        }
//    }
//
//    public func addObserver(_ aName: NSNotification.Name?, object anObject: Any?, selector handler: ClosureWrapper<Notification>)
//    {
//        addObserver(self, selector: #selector(selectorBlockFunc(_:)), name: aName, object: anObject)
//        selectorWrapper = handler
//    }
//
//    @objc
//    private final func selectorBlockFunc(_ sender: Notification)
//    {
//        if let handler = selectorWrapper?.closure
//        {
//            handler(sender)
//        }
//    }
//}

//extension NSLock
//{
//    private struct SwiftyAssociatedKeys {
//        fileprivate static var lockKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
//    }
//
//    private final var lockerHandler : ClosureVoidWrapper? {
//        get {
//            guard let wrapper = objc_getAssociatedObject(self, SwiftyAssociatedKeys.lockKey) as? ClosureVoidWrapper else { return nil }
//            return wrapper
//        }
//        set {
//            objc_setAssociatedObject(self, SwiftyAssociatedKeys.lockKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
//        }
//    }
//
//    public final func locker(_ wrapper: ClosureVoidWrapper)
//    {
//        let lock = NSLock()
//        lock.lock()
//        lockerHandler = wrapper
//        lockerSelector()
//        lock.unlock()
//    }
//
//    private final func lockerSelector()
//    {
//        if let handler = lockerHandler?.closure
//        {
//            handler()
//        }
//    }
//}

extension NSObject
{
    public final class func swizzleInstance(_ originalSelector: Selector, _ swizzledSelector: Selector)
    {
        guard let originalMethod = class_getInstanceMethod(self, originalSelector), let swizzledMethod = class_getInstanceMethod(self, swizzledSelector) else { return }
        
        let isAddMethod : Bool = class_addMethod(self, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        if isAddMethod
        {
            class_replaceMethod(self, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        }
        else
        {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    public final class func swizzleStatic(_ originalSelector: Selector, _ swizzledSelector: Selector)
    {
        guard let swizzledClass = object_getClass(self), let originalMethod = class_getClassMethod(swizzledClass, originalSelector), let swizzledMethod = class_getClassMethod(swizzledClass, swizzledSelector) else { return }
        
        let isAddMethod : Bool = class_addMethod(swizzledClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        if isAddMethod
        {
            class_replaceMethod(swizzledClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        }
        else
        {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}
