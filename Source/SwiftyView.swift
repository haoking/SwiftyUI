//
//  SwiftyView.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/26/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public class SwiftyView : UIView
{
    public init()
    {
        super.init(frame: .zero)
        backgroundColor = .clear
        isHidden = false
        alpha = 1.0
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    public final class func load() -> SwiftyView
//    {
//        return SwiftyView()
//    }
}

public extension UIView
{
    @discardableResult
    final func addTo( _ view: UIView) -> Self
    {
        UIView.methodExchange
        view.addSubview(self)
        return self
    }
    
    private static let methodExchange : Void = {
        
        let originalBackgroundColorSetterSelector : Selector = #selector(setter: backgroundColor)
        let swizzledBackgroundColorSetterSelector : Selector = #selector(updateBackgroundColor(_:))
        swizzleInstance(originalBackgroundColorSetterSelector, swizzledBackgroundColorSetterSelector)
        
        let originalAlphaSelector : Selector = #selector(setter: alpha)
        let swizzledAlphaSelector : Selector = #selector(updateAlpha(_:))
        swizzleInstance(originalAlphaSelector, swizzledAlphaSelector)
    }()
    
    @objc
    private func updateBackgroundColor(_ color: UIColor?)
    {
        updateBackgroundColor(color)
        updateOpaque()
    }
    
    @objc
    private func updateAlpha(_ alpha: CGFloat)
    {
        updateAlpha(alpha)
        updateOpaque()
    }
    
    final func updateOpaque()
    {
        if let color = backgroundColor, color.alphaValue == 1.0, alpha == 1.0
        {
            isOpaque = true
        }
        else
        {
            isOpaque = false
        }
    }
}
