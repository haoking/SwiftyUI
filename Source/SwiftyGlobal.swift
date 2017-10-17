//
//  SwiftyGlobal.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/28/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public final class ClosureVoidWrapper
{
    public final var closure: (() -> Void)?
    
    public init(_ closure: (() -> Void)?) {
        self.closure = closure
    }
}

public final class ClosureWrapper<T>
{
    public final var closure: ((_ obj: T?) -> Void)?
    
    public init(_ closure: ((_ obj: T?) -> Void)?) {
        self.closure = closure
    }
}

public final class ClosureThrowWrapper
{
    public final var closure: (() throws -> Void)?
    
    public init(_ closure: (() throws -> Void)?) {
        self.closure = closure
    }
}

extension NotificationCenter
{
    private struct SwiftyAssociatedKeys {
        fileprivate static var selectorBlockKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    }
    
    private final var selectorWrapper : ClosureWrapper<NotificationCenter>? {
        get {
            guard let wrapper = objc_getAssociatedObject(self, SwiftyAssociatedKeys.selectorBlockKey) as? ClosureWrapper<NotificationCenter> else { return nil }
            return wrapper
        }
        set {
            objc_setAssociatedObject(self, SwiftyAssociatedKeys.selectorBlockKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    public func addObserver(_ observer: Any, name aName: NSNotification.Name?, object anObject: Any?, selector handler: ClosureWrapper<NotificationCenter>)
    {
        self.addObserver(observer, selector: #selector(selectorBlockFunc(_:)), name: aName, object: anObject)
        selectorWrapper = handler
    }
    
    @objc
    private final func selectorBlockFunc(_ sender: NotificationCenter)
    {
        if let handler = selectorWrapper?.closure
        {
            handler(sender)
        }
    }
}

extension NSLock
{
    private struct SwiftyAssociatedKeys {
        fileprivate static var lockKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    }
    
    private final var lockerHandler : ClosureVoidWrapper? {
        get {
            guard let wrapper = objc_getAssociatedObject(self, SwiftyAssociatedKeys.lockKey) as? ClosureVoidWrapper else { return nil }
            return wrapper
        }
        set {
            objc_setAssociatedObject(self, SwiftyAssociatedKeys.lockKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    public final func locker(_ wrapper: ClosureVoidWrapper)
    {
        let lock = NSLock()
        lock.lock()
        lockerHandler = wrapper
        lockerSelector()
        lock.unlock()
    }
    
    private final func lockerSelector()
    {
        if let handler = lockerHandler?.closure
        {
            handler()
        }
    }
}

extension NSObject
{
    public final class func swizzleInstance(_ originalSelector: Selector, _ swizzledSelector: Selector)
    {
        guard let originalMethod = class_getInstanceMethod(self, originalSelector), let swizzledMethod = class_getInstanceMethod(self, swizzledSelector) else { return }
        
        let isAddMethod : Bool = class_addMethod(self, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        if isAddMethod == true
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
        if isAddMethod == true
        {
            class_replaceMethod(swizzledClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        }
        else
        {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}
