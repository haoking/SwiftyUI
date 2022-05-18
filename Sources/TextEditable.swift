//
//  TextEditable.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/30/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

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
    
    fileprivate struct TextEditablePrivateSwiftyAssociatedKeys {
        fileprivate static var containerKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var layoutManagerKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    }
    
    fileprivate struct TextEditablePublicSwiftyAssociatedKeys {
        fileprivate static var usesIntrinsicContentSizeKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var textAlignmentKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var fontKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var textColorKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var paragraphStyleKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var shadowKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
        fileprivate static var attributedTextKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    }
    
    fileprivate func alignOffset(viewSize: CGSize, containerSize: CGSize) -> CGPoint
    {
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

public protocol TextEditable: AnyObject
{
    var usesIntrinsicContentSize: Bool { get set }
    var textAlignment: TextContentAlignment { get set }
    var font : UIFont { get set }
    var textColor : UIColor? { get set }
    var paragraphStyle : NSParagraphStyle { get set }
    var numberOfLines: Int { get set }
    var padding: CGFloat { get set }
    var lineBreakMode: NSLineBreakMode { get set }
    var text: String? { get set }
    var shadow : NSShadow? { get set }
    var attributedText : NSAttributedString? { get set }
    
    func loadText()
}

public extension TextEditable where Self: UIView
{
    //required
    func loadText()
    {
        layoutManager.addTextContainer(container)
    }
    
    //override required
    
    internal func overrideIntrinsicContentSize() -> CGSize
    {
        if usesIntrinsicContentSize
        {
            guard let attributedText = mergedAttributedText else { return .zero }
            let size = CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
            let boundingRect = attributedText.boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            
            return boundingRect.integral.size
        }
        else
        {
            return bounds.size
        }
    }

    internal func overrideDraw(_ rect: CGRect)
    {
        guard let attributedText = mergedAttributedText else { return }
        
        let storage = NSTextStorage(attributedString: attributedText)
        storage.addLayoutManager(layoutManager)
        
        container.size = rect.size
        let frame = layoutManager.usedRect(for: container)
        let point = textAlignment.alignOffset(viewSize: rect.size, containerSize: frame.integral.size)
        
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: point)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: point)
    }
    
    internal func overrideSizeThatFits(_ size: CGSize) -> CGSize
    {
        guard let attributedText = mergedAttributedText else { return .zero }
        
        let storage = NSTextStorage(attributedString: attributedText)
        storage.addLayoutManager(layoutManager)
        
        container.size = size
        let frame = layoutManager.usedRect(for: container)
        return frame.integral.size
    }
    
    internal func overrideSizeToFit()
    {
        frame.size = sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
    }
}

extension TextEditable where Self: UIView
{
    fileprivate var container : NSTextContainer {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePrivateSwiftyAssociatedKeys.containerKey) as? NSTextContainer else {
                
                self.container = NSTextContainer()
                return self.container
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePrivateSwiftyAssociatedKeys.containerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate var layoutManager : NSLayoutManager {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePrivateSwiftyAssociatedKeys.layoutManagerKey) as? NSLayoutManager else {
                
                self.layoutManager = NSLayoutManager()
                return self.layoutManager
                
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePrivateSwiftyAssociatedKeys.layoutManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

public extension TextEditable where Self: UIView
{
    var usesIntrinsicContentSize : Bool {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.usesIntrinsicContentSizeKey) as? Bool else {
                
                usesIntrinsicContentSize = true
                return usesIntrinsicContentSize
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.usesIntrinsicContentSizeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    var textAlignment : TextContentAlignment {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.textAlignmentKey) as? TextContentAlignment else {
                
                textAlignment = .center
                return textAlignment
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.textAlignmentKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    var font : UIFont {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.fontKey) as? UIFont else {
                
                font = .systemFont(ofSize: UIFont.systemFontSize)
                return font
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.fontKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    var textColor : UIColor? {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.textColorKey) as? UIColor else {
                
                textColor = .black
                return textColor
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.textColorKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    var paragraphStyle : NSParagraphStyle {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.paragraphStyleKey) as? NSParagraphStyle else {
                
                paragraphStyle = .default
                return paragraphStyle
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.paragraphStyleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    var shadow : NSShadow? {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.shadowKey) as? NSShadow else { return nil }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.shadowKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    var attributedText : NSAttributedString? {
        get {
            guard let obj = objc_getAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.attributedTextKey) as? NSAttributedString else { return nil }
            return obj
        }
        set {
            objc_setAssociatedObject(self, TextContentAlignment.TextEditablePublicSwiftyAssociatedKeys.attributedTextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
}


public extension TextEditable where Self: UIView
{
    /// default is `0`.
    var numberOfLines: Int {
        get { return container.maximumNumberOfLines }
        set {
            container.maximumNumberOfLines = newValue
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    /// `lineFragmentPadding` of `NSTextContainer`. default is `0`.
    var padding: CGFloat {
        get { return container.lineFragmentPadding }
        set {
            container.lineFragmentPadding = newValue
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    /// default is `ByTruncatingTail`.
    var lineBreakMode: NSLineBreakMode {
        get { return container.lineBreakMode }
        set {
            container.lineBreakMode = newValue
            if Thread.isMainThread
            {
                setNeedsDisplay()
            }
        }
    }
    
    /// default is nil.
    var text: String? {
        get {
            return attributedText?.string
        }
        set {
            if let value = newValue {
                attributedText = NSAttributedString(string: value)
            } else {
                attributedText = nil
            }
        }
    }
    
    var mergedAttributedText: NSAttributedString? {
        if let attributedText = attributedText {
            return mergeAttributes(attributedText)
        }
        return nil
    }
    
    fileprivate func mergeAttributes(_ attributedText: NSAttributedString) -> NSAttributedString
    {
        let attrString = NSMutableAttributedString(attributedString: attributedText)
        
        attrString.addAttribute(.font, attr: font)
        attrString.addAttribute(.foregroundColor, attr: textColor!)
        attrString.addAttribute(.paragraphStyle, attr: paragraphStyle)
        
        if let shadow = shadow
        {
            attrString.addAttribute(.shadow, attr: shadow)
        }
        
        return attrString
    }
}

fileprivate extension NSMutableAttributedString
{
    @discardableResult
    final func addAttribute(_ attrName: NSAttributedString.Key, attr: AnyObject, in range: NSRange? = nil) -> Self
    {
        let range = range ?? NSRange(location: 0, length: length)
        enumerateAttribute(attrName, in: range, options: .reverse) { object, range, pointer in
            if object == nil
            {
                addAttributes([attrName: attr], range: range)
            }
        }
        return self
    }
}
