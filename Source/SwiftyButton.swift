//
//  SwiftyButton.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/22/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public class SwiftyButton: UIControl, ImageSettable
{
    public lazy var titleLabel: SwiftyLabel = { [unowned self] in
        var titleLabel : SwiftyLabel = .load(nil, .black, .clear)
        titleLabel.addTo(self)
        titleLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return titleLabel
        }()
    
    private init(_ title: String? = nil, _ image: UIImage? = nil, _ handler: ClosureWrapper<SwiftyButton>)
    {
        super.init(frame: .zero)
        UIButton.methodExchange
        addHandler(handler)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isHidden = false
        alpha = 1.0
        titleLabel.text = title
        backgroundImage = image
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public final class func load(_ title: String? = nil, _ image: UIImage? = nil, _ handler: ClosureWrapper<SwiftyButton>) -> SwiftyButton
    {
        return SwiftyButton.init(title, image, handler)
    }
}

extension SwiftyButton
{
    private struct SwiftyAssociatedKeys {
        fileprivate static var tapHandlerKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var tapForwardHandlerKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    }
    
    private var tapHandlerWrapper : ClosureWrapper<SwiftyButton>? {
        get {
            guard let wrapper = objc_getAssociatedObject(self, SwiftyAssociatedKeys.tapHandlerKey) as? ClosureWrapper<SwiftyButton> else { return nil }
            return wrapper
        }
        set {
            objc_setAssociatedObject(self, SwiftyAssociatedKeys.tapHandlerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate func addHandler(_ handler: ClosureWrapper<SwiftyButton>)
    {
        tapHandlerWrapper = handler
        self.addTarget(self, action: #selector(btnTapped(_:)), for: .touchUpInside)
    }
    
    @objc private func btnTapped(_ sender: SwiftyButton)
    {
        if let handler = tapHandlerWrapper?.closure
        {
            handler(sender)
        }
    }
}

extension UIControl
{
    private struct SwiftyAssociatedKeys {
        fileprivate static var isIgnoreEventKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    }
    
    private var isIgnoreEvent : Bool? {
        get {
            guard let obj = objc_getAssociatedObject(self, SwiftyAssociatedKeys.isIgnoreEventKey) as? Bool else {
                
                self.isIgnoreEvent = false
                return self.isIgnoreEvent
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, SwiftyAssociatedKeys.isIgnoreEventKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate static let methodExchange : Void = {
        
        let originalSelector : Selector = #selector(sendAction(_:to:for:))
        let swizzledSelector : Selector = #selector(mySendAction(_:to:for:))
        swizzleInstance(originalSelector, swizzledSelector)
    }()
    
    @objc private func mySendAction(_ action: Selector, to target: Any?, for event: UIEvent?)
    {
        guard isIgnoreEvent == false else { return }
        perform(#selector(resetState), with: self, afterDelay: 1.0)
        isIgnoreEvent = true
        mySendAction(action, to: target, for: event)
    }
    
    @objc private func resetState()
    {
        isIgnoreEvent = false
    }
}






