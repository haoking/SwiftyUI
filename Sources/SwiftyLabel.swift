//
//  SwiftyLabel.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/26/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public class SwiftyLabel: UIView, TextEditable
{
    public init(_ text: String? = nil, _ textColor: UIColor? = nil, _ backgroundColor: UIColor? = nil)
    {
        super.init(frame: .zero)
        loadText()
        usesIntrinsicContentSize = true
        textAlignment = .center
        font = .systemFont(ofSize: UIFont.systemFontSize)
        paragraphStyle = .default
        numberOfLines = 0
        padding = 0
        lineBreakMode = .byTruncatingTail
        
        isHidden = false
        alpha = 1.0
        contentMode = .redraw
        isUserInteractionEnabled = false
        
        self.text = text
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
    
    public required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
//    public final class func load(_ text: String? = nil, _ textColor: UIColor? = nil, _ backgroundColor: UIColor? = nil) -> SwiftyLabel
//    {
//        return SwiftyLabel(text, textColor, backgroundColor)
//    }
}

extension SwiftyLabel
{
    open override var intrinsicContentSize: CGSize
    {
        return overrideIntrinsicContentSize()
    }
    
    open override func draw(_ rect: CGRect)
    {
        overrideDraw(rect)
    }
    
    open override func sizeThatFits(_ size: CGSize) -> CGSize
    {
        return overrideSizeThatFits(size)
    }
    
    open override func sizeToFit()
    {
        super.sizeToFit()
        overrideSizeToFit()
    }
}


