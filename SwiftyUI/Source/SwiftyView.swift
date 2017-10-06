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

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIView
{
    @discardableResult
    public func addTo( _ view: UIView) -> Self
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
        
        let originalBackgroundColorGetterSelector : Selector = #selector(getter: backgroundColor)
        let swizzledBackgroundColorGetterSelector : Selector = #selector(currentBackgroundColor)
        swizzleInstance(originalBackgroundColorGetterSelector, swizzledBackgroundColorGetterSelector)
    }()
    
    @objc private func updateBackgroundColor(_ color: UIColor?)
    {
        layer.backgroundColor = color?.cgColor
        updateOpaque()
    }
    
    @objc private func currentBackgroundColor() -> UIColor?
    {
        guard let currentColor = layer.backgroundColor else { return nil }
        return UIColor(cgColor: currentColor)
    }
    
    @objc private func updateAlpha(_ alpha: CGFloat)
    {
        updateAlpha(alpha)
        updateOpaque()
    }
    
    open func updateOpaque()
    {
        if let color = layer.backgroundColor, UIColor(cgColor: color).alphaValue == 1.0, alpha == 1.0
        {
            isOpaque = true
        }
        else
        {
            isOpaque = false
        }
    }
}
