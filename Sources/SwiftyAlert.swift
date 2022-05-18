//
//  SwiftyAlert.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/30/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public enum SwiftyAlertViewStyle
{
    case success, error, warning, info, edit

    public var defaultColorInt: UInt {
        switch self {
        case .success:
            return 0x22B573
        case .error:
            return 0xC1272D
        case .warning:
            return 0xFFD110
        case .info:
            return 0x2866BF
        case .edit:
            return 0xA429FF
        }
    }
}

public enum SwiftyAlertButtonLayout
{
    case horizontal, vertical
}

open class SwiftyAlertButton: UIButton
{
    var action:(()->Void)!
}

// Allow alerts to be closed/renamed in a chainable manner
// Example: SwiftyAlertView().showSuccess(self, title: "Test", subTitle: "Value").close()
public final class SwiftyAlertViewResponder
{
    let alertview: SwiftyAlertView
    
    // Initialisation and Title/Subtitle/Close functions
    public init(alertview: SwiftyAlertView)
    {
        self.alertview = alertview
    }
    
    public func setTitle(_ title: String)
    {
        self.alertview.labelTitle.text = title
    }
    
    public func setSubTitle(_ subTitle: String)
    {
        self.alertview.viewText.text = subTitle
    }
    
    public func close()
    {
        self.alertview.hideView()
    }
    
    public func setDismissBlock(_ dismissBlock: @escaping () -> Void)
    {
        self.alertview.dismissBlock = dismissBlock
    }
}

fileprivate let kCircleHeightBackground: CGFloat = 62.0
fileprivate let uniqueTag: Int = Int(arc4random() % UInt32(Int32.max))
fileprivate let uniqueAccessibilityIdentifier: String = "SwiftyAlert"

//public typealias DismissBlock = () -> Void

// The Main Class
public final class SwiftyAlertView: UIViewController
{
    public struct SwiftyAppearance
    {
        let kDefaultShadowOpacity: CGFloat
        let kCircleTopPosition: CGFloat
        let kCircleBackgroundTopPosition: CGFloat
        let kCircleHeight: CGFloat
        let kCircleIconHeight: CGFloat
        let kTitleTop:CGFloat
        let kTitleHeight:CGFloat
        let kTitleMinimumScaleFactor: CGFloat
        let kWindowWidth: CGFloat
        var kWindowHeight: CGFloat
        var kTextHeight: CGFloat
        let kTextFieldHeight: CGFloat
        let kTextViewdHeight: CGFloat
        let kButtonHeight: CGFloat
        let circleBackgroundColor: UIColor
        let contentViewColor: UIColor
        let contentViewBorderColor: UIColor
        let titleColor: UIColor
        
        // Fonts
        let kTitleFont: UIFont
        let kTextFont: UIFont
        let kButtonFont: UIFont
        
        // UI Options
        var disableTapGesture: Bool
//        var showCloseButton: Bool
        var showCircularIcon: Bool
        var shouldAutoDismiss: Bool // Set this false to 'Disable' Auto hideView when SwiftyAlertButton is tapped
        var contentViewCornerRadius : CGFloat
        var fieldCornerRadius : CGFloat
        var buttonCornerRadius : CGFloat
        var buttonsLayout: SwiftyAlertButtonLayout
        
        // Actions
        var hideWhenBackgroundViewIsTapped: Bool
        
        public init(kDefaultShadowOpacity: CGFloat = 0.7, kCircleTopPosition: CGFloat = 0.0, kCircleBackgroundTopPosition: CGFloat = 6.0, kCircleHeight: CGFloat = 56.0, kCircleIconHeight: CGFloat = 20.0, kTitleTop:CGFloat = 30.0, kTitleHeight:CGFloat = 25.0,  kWindowWidth: CGFloat = 240.0, kWindowHeight: CGFloat = 178.0, kTextHeight: CGFloat = 90.0, kTextFieldHeight: CGFloat = 45.0, kTextViewdHeight: CGFloat = 80.0, kButtonHeight: CGFloat = 45.0, kTitleFont: UIFont = UIFont.systemFont(ofSize: 20), kTitleMinimumScaleFactor: CGFloat = 1.0, kTextFont: UIFont = UIFont.systemFont(ofSize: 14), kButtonFont: UIFont = UIFont.boldSystemFont(ofSize: 14), showCircularIcon: Bool = true, shouldAutoDismiss: Bool = true, contentViewCornerRadius: CGFloat = 5.0, fieldCornerRadius: CGFloat = 3.0, buttonCornerRadius: CGFloat = 3.0, hideWhenBackgroundViewIsTapped: Bool = false, circleBackgroundColor: UIColor = UIColor.white, contentViewColor: UIColor = .hex(0xFFFFFF), contentViewBorderColor: UIColor = .hex(0xCCCCCC), titleColor: UIColor = .hex(0x4D4D4D), dynamicAnimatorActive: Bool = false, disableTapGesture: Bool = false, buttonsLayout: SwiftyAlertButtonLayout = .vertical)
        {
            self.kDefaultShadowOpacity = kDefaultShadowOpacity
            self.kCircleTopPosition = kCircleTopPosition
            self.kCircleBackgroundTopPosition = kCircleBackgroundTopPosition
            self.kCircleHeight = kCircleHeight
            self.kCircleIconHeight = kCircleIconHeight
            self.kTitleTop = kTitleTop
            self.kTitleHeight = kTitleHeight
            self.kWindowWidth = kWindowWidth
            self.kWindowHeight = kWindowHeight
            self.kTextHeight = kTextHeight
            self.kTextFieldHeight = kTextFieldHeight
            self.kTextViewdHeight = kTextViewdHeight
            self.kButtonHeight = kButtonHeight
            self.circleBackgroundColor = circleBackgroundColor
            self.contentViewColor = contentViewColor
            self.contentViewBorderColor = contentViewBorderColor
            self.titleColor = titleColor
            
            self.kTitleFont = kTitleFont
            self.kTitleMinimumScaleFactor = kTitleMinimumScaleFactor
            self.kTextFont = kTextFont
            self.kButtonFont = kButtonFont
            
            self.disableTapGesture = disableTapGesture
            self.showCircularIcon = showCircularIcon
            self.shouldAutoDismiss = shouldAutoDismiss
            self.contentViewCornerRadius = contentViewCornerRadius
            self.fieldCornerRadius = fieldCornerRadius
            self.buttonCornerRadius = buttonCornerRadius
            
            self.hideWhenBackgroundViewIsTapped = hideWhenBackgroundViewIsTapped
            self.buttonsLayout = buttonsLayout
            
        }
        
        mutating func setkWindowHeight(_ kWindowHeight:CGFloat)
        {
            self.kWindowHeight = kWindowHeight
        }
        
        mutating func setkTextHeight(_ kTextHeight:CGFloat)
        {
            self.kTextHeight = kTextHeight
        }
    }
    
    var appearance: SwiftyAppearance!
    
    // UI Colour
    var viewColor = UIColor()
    
    // UI Options
    public var iconTintColor: UIColor?
//    open var customSubview : UIView?
    
    // Members declaration
    var baseView = UIView()
    var labelTitle = UILabel()
    var viewText = UITextView()
    var contentView = UIView()
    var circleBG = UIView(frame:CGRect(x:0, y:0, width:kCircleHeightBackground, height:kCircleHeightBackground))
    var circleView = UIView()
    var circleIconView : UIView?
    var dismissBlock : (() -> Void)?
    fileprivate var inputs = [UITextField]()
    fileprivate var input = [UITextView]()
    internal var buttons = [SwiftyAlertButton]()
    fileprivate var selfReference: SwiftyAlertView?
    
    private init(_ appearance: SwiftyAppearance)
    {
        self.appearance = appearance
        super.init(nibName:nil, bundle:nil)
        setup()
    }
    
    required public init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    public final class func create(_ appearance: SwiftyAppearance = SwiftyAppearance()) -> SwiftyAlertView
    {
        return SwiftyAlertView(appearance)
    }
    
    
    fileprivate func setup()
    {
        // Set up main view
        view.frame = UIScreen.main.bounds
        view.autoresizingMask = [UIView.AutoresizingMask.flexibleHeight, UIView.AutoresizingMask.flexibleWidth]
        view.backgroundColor = UIColor(red:0, green:0, blue:0, alpha:appearance.kDefaultShadowOpacity)
        view.addSubview(baseView)
        // Base View
        baseView.frame = view.frame
        baseView.addSubview(contentView)
        // Content View
        contentView.layer.cornerRadius = appearance.contentViewCornerRadius
        contentView.layer.masksToBounds = true
        contentView.layer.borderWidth = 0.5
        contentView.addSubview(labelTitle)
        contentView.addSubview(viewText)
        // Circle View
        circleBG.backgroundColor = appearance.circleBackgroundColor
        circleBG.layer.cornerRadius = circleBG.frame.size.height / 2
        baseView.addSubview(circleBG)
        circleBG.addSubview(circleView)
        let x = (kCircleHeightBackground - appearance.kCircleHeight) / 2
        circleView.frame = CGRect(x:x, y:x+appearance.kCircleTopPosition, width:appearance.kCircleHeight, height:appearance.kCircleHeight)
        circleView.layer.cornerRadius = circleView.frame.size.height / 2
        // Title
        labelTitle.numberOfLines = 0
        labelTitle.textAlignment = .center
        labelTitle.font = appearance.kTitleFont
        if(appearance.kTitleMinimumScaleFactor < 1)
        {
            labelTitle.minimumScaleFactor = appearance.kTitleMinimumScaleFactor
            labelTitle.adjustsFontSizeToFitWidth = true
        }
        labelTitle.frame = CGRect(x:12, y:appearance.kTitleTop, width: appearance.kWindowWidth - 24, height:appearance.kTitleHeight)
        // View text
        viewText.isEditable = false
        viewText.isSelectable = false
        viewText.textAlignment = .center
        viewText.textContainerInset = UIEdgeInsets.zero
        viewText.textContainer.lineFragmentPadding = 0;
        viewText.font = appearance.kTextFont
        // Colours
        contentView.backgroundColor = appearance.contentViewColor
        viewText.backgroundColor = appearance.contentViewColor
        labelTitle.textColor = appearance.titleColor
        viewText.textColor = appearance.titleColor
        contentView.layer.borderColor = appearance.contentViewBorderColor.cgColor
        //Gesture Recognizer for tapping outside the textinput
        if !appearance.disableTapGesture
        {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(SwiftyAlertView.tapped(_:)))
            tapGesture.numberOfTapsRequired = 1
            self.view.addGestureRecognizer(tapGesture)
        }
    }
    
    override public func viewWillLayoutSubviews()
    {
        super.viewWillLayoutSubviews()
        let rv: UIWindow = UIApplication.shared.keyWindow!
        let sz = rv.frame.size
        
        // Set background frame
        view.frame.size = sz
        
        let hMargin: CGFloat = 12
        let defaultTopOffset: CGFloat = 32
        
        // get actual height of title text
        var titleActualHeight: CGFloat = 0
        if let title = labelTitle.text
        {
            titleActualHeight = title.heightWithConstrainedWidth(width: appearance.kWindowWidth - hMargin * 2, font: labelTitle.font) + 10
            // get the larger height for the title text
            titleActualHeight = (titleActualHeight > appearance.kTitleHeight ? titleActualHeight : appearance.kTitleHeight)
        }
        
        // computing the right size to use for the textView
        let maxHeight = sz.height - 100 // max overall height
        var consumedHeight = CGFloat(0)
        consumedHeight += (titleActualHeight > 0 ? appearance.kTitleTop + titleActualHeight : defaultTopOffset)
        consumedHeight += 14
        
        if appearance.buttonsLayout == .vertical
        {
            consumedHeight += appearance.kButtonHeight * CGFloat(buttons.count)
        }
        else
        {
            consumedHeight += appearance.kButtonHeight
        }
        consumedHeight += appearance.kTextFieldHeight * CGFloat(inputs.count)
        consumedHeight += appearance.kTextViewdHeight * CGFloat(input.count)
        let maxViewTextHeight = maxHeight - consumedHeight
        let viewTextWidth = appearance.kWindowWidth - hMargin * 2
        var viewTextHeight = appearance.kTextHeight
        
        let suggestedViewTextSize = viewText.sizeThatFits(CGSize(width: viewTextWidth, height: CGFloat.greatestFiniteMagnitude))
        viewTextHeight = min(suggestedViewTextSize.height, maxViewTextHeight)
        
        // scroll management
        if (suggestedViewTextSize.height > maxViewTextHeight)
        {
            viewText.isScrollEnabled = true
        }
        else
        {
            viewText.isScrollEnabled = false
        }
        
        let windowHeight = consumedHeight + viewTextHeight
        // Set frames
        var x = (sz.width - appearance.kWindowWidth) / 2
        var y = (sz.height - windowHeight - (appearance.kCircleHeight / 8)) / 2
        contentView.frame = CGRect(x:x, y:y, width:appearance.kWindowWidth, height:windowHeight)
        contentView.layer.cornerRadius = appearance.contentViewCornerRadius
        y -= kCircleHeightBackground * 0.6
        x = (sz.width - kCircleHeightBackground) / 2
        circleBG.frame = CGRect(x:x, y:y+appearance.kCircleBackgroundTopPosition, width:kCircleHeightBackground, height:kCircleHeightBackground)
        
        //adjust Title frame based on circularIcon show/hide flag
        //        let titleOffset : CGFloat = appearance.showCircularIcon ? 0.0 : -12.0
        let titleOffset: CGFloat = 0
        labelTitle.frame = labelTitle.frame.offsetBy(dx: 0, dy: titleOffset)
        
        // Subtitle
        y = titleActualHeight > 0 ? appearance.kTitleTop + titleActualHeight + titleOffset : defaultTopOffset
        viewText.frame = CGRect(x:hMargin, y:y, width: appearance.kWindowWidth - hMargin * 2, height:appearance.kTextHeight)
        viewText.frame = CGRect(x:hMargin, y:y, width: viewTextWidth, height:viewTextHeight)
        // Text fields
        y += viewTextHeight + 14.0
        for (_, txt) in inputs.enumerated()
        {
            txt.frame = CGRect(x:hMargin, y:y, width:appearance.kWindowWidth - hMargin * 2, height:30)
            txt.layer.cornerRadius = appearance.fieldCornerRadius
            y += appearance.kTextFieldHeight
        }
        for (_, txt) in input.enumerated()
        {
            txt.frame = CGRect(x:hMargin, y:y, width:appearance.kWindowWidth - hMargin * 2, height:appearance.kTextViewdHeight - hMargin)
            //txt.layer.cornerRadius = fieldCornerRadius
            y += appearance.kTextViewdHeight
        }
        // Buttons
        let numberOfButton = CGFloat(buttons.count)
        let buttonsSpace = numberOfButton >= 1 ? CGFloat(10) * (numberOfButton - 1) : 0
        let widthEachButton = (appearance.kWindowWidth - 24 - buttonsSpace) / numberOfButton
        var buttonX = CGFloat(12)
        
        switch appearance.buttonsLayout {
        case .vertical:
            for (_, btn) in buttons.enumerated()
            {
                btn.frame = CGRect(x:12, y:y, width:appearance.kWindowWidth - 24, height:35)
                btn.layer.cornerRadius = appearance.buttonCornerRadius
                y += appearance.kButtonHeight
            }
        case .horizontal:
            for (_, btn) in buttons.enumerated()
            {
                btn.frame = CGRect(x:buttonX, y:y, width: widthEachButton, height:35)
                btn.layer.cornerRadius = appearance.buttonCornerRadius
                buttonX += widthEachButton
                buttonX += buttonsSpace
            }
        }
    }
    
    var tmpContentViewFrameOrigin: CGPoint?
    var tmpCircleViewFrameOrigin: CGPoint?
    var keyboardHasBeenShown:Bool = false
    
    override public func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] (notification) in
            
            guard let strongSelf = self else { return }
            strongSelf.keyboardHasBeenShown = true
            guard let userInfo = notification.userInfo else {return}
            guard let endKeyBoardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.minY else {return}
            
            if strongSelf.tmpContentViewFrameOrigin == nil
            {
                strongSelf.tmpContentViewFrameOrigin = strongSelf.contentView.frame.origin
            }
            
            if strongSelf.tmpCircleViewFrameOrigin == nil
            {
                strongSelf.tmpCircleViewFrameOrigin = strongSelf.circleBG.frame.origin
            }
            
            var newContentViewFrameY = strongSelf.contentView.frame.maxY - endKeyBoardFrame
            if newContentViewFrameY < 0
            {
                newContentViewFrameY = 0
            }
            
            let newBallViewFrameY = strongSelf.circleBG.frame.origin.y - newContentViewFrameY
            strongSelf.contentView.frame.origin.y -= newContentViewFrameY
            strongSelf.circleBG.frame.origin.y = newBallViewFrameY
        }

        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] (notification) in
            
            guard let strongSelf = self else { return }
            if(strongSelf.keyboardHasBeenShown)
            {//This could happen on the simulator (keyboard will be hidden)
                if(strongSelf.tmpContentViewFrameOrigin != nil)
                {
                    strongSelf.contentView.frame.origin.y = strongSelf.tmpContentViewFrameOrigin!.y
                    strongSelf.tmpContentViewFrameOrigin = nil
                }
                if(strongSelf.tmpCircleViewFrameOrigin != nil)
                {
                    strongSelf.circleBG.frame.origin.y = strongSelf.tmpCircleViewFrameOrigin!.y
                    strongSelf.tmpCircleViewFrameOrigin = nil
                }
                
                strongSelf.keyboardHasBeenShown = false
            }
            
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    override public func touchesEnded(_ touches:Set<UITouch>, with event:UIEvent?)
    {
        if let count = event?.touches(for: view)?.count, count > 0
        {
            view.endEditing(true)
        }
    }
    
    public func addTextField(_ title:String?=nil) -> UITextField
    {
        // Update view height
        appearance.setkWindowHeight(appearance.kWindowHeight + appearance.kTextFieldHeight)
        // Add text field
        let txt = UITextField()
        txt.borderStyle = UITextField.BorderStyle.roundedRect
        txt.font = appearance.kTextFont
        txt.autocapitalizationType = UITextAutocapitalizationType.words
        txt.clearButtonMode = UITextField.ViewMode.whileEditing
        txt.layer.masksToBounds = true
        txt.layer.borderWidth = 1.0
        txt.placeholder = title
        contentView.addSubview(txt)
        inputs.append(txt)
        return txt
    }
    
    public func addTextView() -> UITextView
    {
        // Update view height
        appearance.setkWindowHeight(appearance.kWindowHeight + appearance.kTextViewdHeight)
        // Add text view
        let txt = UITextView()
        txt.font = appearance.kTextFont
        txt.layer.masksToBounds = true
        txt.layer.borderWidth = 1.0
        contentView.addSubview(txt)
        input.append(txt)
        return txt
    }
    
    @discardableResult
    public func addButton(_ title:String, action:@escaping ()->Void) -> SwiftyAlertButton
    {
        appearance.setkWindowHeight(appearance.kWindowHeight + appearance.kButtonHeight)
        // Add button
        let btn = SwiftyAlertButton()
        btn.layer.masksToBounds = true
        btn.setTitle(title, for: UIControl.State())
        btn.titleLabel?.font = appearance.kButtonFont

        btn.action = action
        
        btn.addTarget(self, action:#selector(SwiftyAlertView.buttonTapped(_:)), for:.touchUpInside)
        btn.addTarget(self, action:#selector(SwiftyAlertView.buttonTapDown(_:)), for:[.touchDown, .touchDragEnter])
        btn.addTarget(self, action:#selector(SwiftyAlertView.buttonRelease(_:)), for:[.touchUpInside, .touchUpOutside, .touchCancel, .touchDragOutside])
        
        contentView.addSubview(btn)
        buttons.append(btn)
        return btn
    }
    
    @objc
    func buttonTapped(_ btn:SwiftyAlertButton)
    {
        btn.action()
        if(self.view.alpha != 0.0 && appearance.shouldAutoDismiss) { hideView() }
    }
    
    
    @objc
    func buttonTapDown(_ btn:SwiftyAlertButton)
    {
        var hue : CGFloat = 0
        var saturation : CGFloat = 0
        var brightness : CGFloat = 0
        var alpha : CGFloat = 0
        let pressBrightnessFactor = 0.85
        btn.backgroundColor?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        brightness = brightness * CGFloat(pressBrightnessFactor)
        btn.backgroundColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
    
    @objc
    func buttonRelease(_ btn:SwiftyAlertButton)
    {
        btn.backgroundColor = viewColor
    }

    //Dismiss keyboard when tapped outside textfield & close SwiftyAlertView when hideWhenBackgroundViewIsTapped
    @objc func tapped(_ gestureRecognizer: UITapGestureRecognizer)
    {
        self.view.endEditing(true)
        
        if let tappedView = gestureRecognizer.view , tappedView.hitTest(gestureRecognizer.location(in: tappedView), with: nil) == baseView && appearance.hideWhenBackgroundViewIsTapped
        {
            hideView()
        }
    }
    
    // showSuccess(view, title, subTitle)
    @discardableResult
    public func showSuccess(_ title: String, subTitle: String, colorStyle: UInt=SwiftyAlertViewStyle.success.defaultColorInt, colorTextButton: UInt=0xFFFFFF, circleIconImage: UIImage? = nil) -> SwiftyAlertViewResponder
    {
        return showTitle(title, subTitle: subTitle, style: .success, colorStyle: colorStyle, colorTextButton: colorTextButton, circleIconImage: circleIconImage)
    }
    
    // showError(view, title, subTitle)
    @discardableResult
    public func showError(_ title: String, subTitle: String, colorStyle: UInt=SwiftyAlertViewStyle.error.defaultColorInt, colorTextButton: UInt=0xFFFFFF, circleIconImage: UIImage? = nil) -> SwiftyAlertViewResponder
    {
        return showTitle(title, subTitle: subTitle, style: .error, colorStyle: colorStyle, colorTextButton: colorTextButton, circleIconImage: circleIconImage)
    }
    
    // showWarning(view, title, subTitle)
    @discardableResult
    public func showWarning(_ title: String, subTitle: String, colorStyle: UInt=SwiftyAlertViewStyle.warning.defaultColorInt, colorTextButton: UInt=0x000000, circleIconImage: UIImage? = nil) -> SwiftyAlertViewResponder
    {
        return showTitle(title, subTitle: subTitle, style: .warning, colorStyle: colorStyle, colorTextButton: colorTextButton, circleIconImage: circleIconImage)
    }
    
    // showInfo(view, title, subTitle)
    @discardableResult
    public func showInfo(_ title: String, subTitle: String, colorStyle: UInt=SwiftyAlertViewStyle.info.defaultColorInt, colorTextButton: UInt=0xFFFFFF, circleIconImage: UIImage? = nil) -> SwiftyAlertViewResponder
    {
        return showTitle(title, subTitle: subTitle, style: .info, colorStyle: colorStyle, colorTextButton: colorTextButton, circleIconImage: circleIconImage)
    }
    
    @discardableResult
    public func showEdit(_ title: String, subTitle: String, colorStyle: UInt=SwiftyAlertViewStyle.edit.defaultColorInt, colorTextButton: UInt=0xFFFFFF, circleIconImage: UIImage? = nil) -> SwiftyAlertViewResponder
    {
        return showTitle(title, subTitle: subTitle, style: .edit, colorStyle: colorStyle, colorTextButton: colorTextButton, circleIconImage: circleIconImage)
    }
    
    // showTitle(view, title, subTitle, timeout, style)
    @discardableResult
    public func showTitle(_ title: String, subTitle: String, style: SwiftyAlertViewStyle, colorStyle: UInt?=0x000000, colorTextButton: UInt?=0xFFFFFF, circleIconImage: UIImage? = nil) -> SwiftyAlertViewResponder
    {
        selfReference = self
        view.alpha = 0
        view.tag = uniqueTag
        view.accessibilityIdentifier = uniqueAccessibilityIdentifier
        let rv = UIApplication.shared.keyWindow! as UIWindow
        rv.addSubview(view)
        view.frame = rv.bounds
        baseView.frame = rv.bounds
        
        // Alert colour/icon
        viewColor = UIColor()
        var iconImage: UIImage?
        let colorInt = colorStyle ?? style.defaultColorInt
        viewColor = UIColor.hex(colorInt)
        
        // Icon style
        switch style {
        case .success:
            
            iconImage = checkCircleIconImage(circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfCheckmark)
            
        case .error:
            
            iconImage = checkCircleIconImage(circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfCross)
            
        case .warning:
            
            iconImage = checkCircleIconImage(circleIconImage, defaultImage:SwiftyAlertViewStyleKit.imageOfWarning)
            
        case .info:
            
            iconImage = checkCircleIconImage(circleIconImage, defaultImage:SwiftyAlertViewStyleKit.imageOfInfo)
            
        case .edit:
            
            iconImage = checkCircleIconImage(circleIconImage, defaultImage:SwiftyAlertViewStyleKit.imageOfEdit)
            
        }
        
        // Title
        if !title.isEmpty
        {
            self.labelTitle.text = title
            let actualHeight = title.heightWithConstrainedWidth(width: appearance.kWindowWidth - 24, font: self.labelTitle.font)
            self.labelTitle.frame = CGRect(x:12, y:appearance.kTitleTop, width: appearance.kWindowWidth - 24, height:actualHeight)
        }
        
        // Subtitle
        if !subTitle.isEmpty
        {
            viewText.text = subTitle
            // Adjust text view size, if necessary
            let str = subTitle as NSString
            let attr = [NSAttributedString.Key.font:viewText.font ?? UIFont()]
            let sz = CGSize(width: appearance.kWindowWidth - 24, height:90)
            let r = str.boundingRect(with: sz, options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes:attr, context:nil)
            let ht = ceil(r.size.height)
            if ht < appearance.kTextHeight
            {
                appearance.kWindowHeight -= (appearance.kTextHeight - ht)
                appearance.setkTextHeight(ht)
            }
        }
        
        //hidden/show circular view based on the ui option
        circleView.isHidden = !appearance.showCircularIcon
        circleBG.isHidden = !appearance.showCircularIcon
        
        // Alert view colour and images
        circleView.backgroundColor = viewColor
        
        if let iconTintColor = iconTintColor
        {
            circleIconView = UIImageView(image: iconImage!.withRenderingMode(.alwaysTemplate))
            circleIconView?.tintColor = iconTintColor
        }
        else
        {
            circleIconView = UIImageView(image: iconImage!)
        }

        circleView.addSubview(circleIconView!)
        let x = (appearance.kCircleHeight - appearance.kCircleIconHeight) / 2
        circleIconView!.frame = CGRect( x: x, y: x, width: appearance.kCircleIconHeight, height: appearance.kCircleIconHeight)
        circleIconView?.layer.masksToBounds = true
        
        for (_, txt) in inputs.enumerated()
        {
            txt.layer.borderColor = viewColor.cgColor
        }
        
        for (_, txt) in input.enumerated()
        {
            txt.layer.borderColor = viewColor.cgColor
        }
        
        for (_, btn) in buttons.enumerated()
        {
            btn.backgroundColor = viewColor
            btn.setTitleColor(UIColor.hex(colorTextButton ?? 0xFFFFFF), for: UIControl.State())
        }
        
        // Animate in the alert view
        self.showAnimation()
        
        // Chainable objects
        return SwiftyAlertViewResponder(alertview: self)
    }
    
    // Show animation in the alert view
    fileprivate func showAnimation(animationStartOffset: CGFloat = -400.0, boundingAnimationOffset: CGFloat = 15.0, animationDuration: TimeInterval = 0.2)
    {
        
        let rv = UIApplication.shared.keyWindow! as UIWindow
        var animationStartOrigin = self.baseView.frame.origin
        var animationCenter : CGPoint = rv.center
        
        animationStartOrigin = CGPoint(x: animationStartOrigin.x, y: self.baseView.frame.origin.y + animationStartOffset)
        animationCenter = CGPoint(x: animationCenter.x, y: animationCenter.y + boundingAnimationOffset)
        
        self.baseView.frame.origin = animationStartOrigin
        
        UIView.animate(withDuration: animationDuration, animations: {
            self.view.alpha = 1.0
            self.baseView.center = animationCenter
        }, completion: { finished in
            UIView.animate(withDuration: animationDuration, animations: {
                self.view.alpha = 1.0
                self.baseView.center = rv.center
            })
        })
    }
    
    // DynamicAnimator function
    var animator : UIDynamicAnimator?
    var snapBehavior : UISnapBehavior?
    
    fileprivate func animate(item : UIView , center: CGPoint)
    {
        if let snapBehavior = self.snapBehavior
        {
            self.animator?.removeBehavior(snapBehavior)
        }
        
        self.animator = UIDynamicAnimator.init(referenceView: self.view)
        let tempSnapBehavior  =  UISnapBehavior.init(item: item, snapTo: center)
        self.animator?.addBehavior(tempSnapBehavior)
        self.snapBehavior? = tempSnapBehavior
    }
    
    // Close SwiftyAlertView
    @objc
    public func hideView()
    {
        UIView.animate(withDuration: 0.2, animations: {
            self.view.alpha = 0
        }, completion: { finished in
            
            if let dismissBlock = self.dismissBlock
            {
                dismissBlock()
            }
            
            // This is necessary for SwiftyAlertView to be de-initialized, preventing a strong reference cycle with the viewcontroller calling SwiftyAlertView.
            for (_, button) in self.buttons.enumerated()
            {
                button.action = nil
            }
            
            self.view.removeFromSuperview()
            self.selfReference = nil
        })
    }
    
    func checkCircleIconImage(_ circleIconImage: UIImage?, defaultImage: UIImage) -> UIImage
    {
        if let image = circleIconImage
        {
            return image
        }
        else
        {
            return defaultImage
        }
    }
    
    //Return true if a SwiftyAlertView is already being shown, false otherwise
    public func isShowing() -> Bool
    {
        if let subviews = UIApplication.shared.keyWindow?.subviews
        {
            for (_, view) in subviews.enumerated()
            {
                if view.tag == uniqueTag && view.accessibilityIdentifier == uniqueAccessibilityIdentifier
                {
                    return true
                }
            }
        }
        return false
    }
}

// ------------------------------------
// Icon drawing
// Code generated by PaintCode
// ------------------------------------

fileprivate final class SwiftyAlertViewStyleKit : NSObject
{
    // Cache
    struct Cache
    {
        static var imageOfCheckmark: UIImage?
        static var imageOfCross: UIImage?
        static var imageOfWarning: UIImage?
        static var imageOfInfo: UIImage?
        static var imageOfEdit: UIImage?
    }
    
    // Drawing Methods
    class func drawCheckmark()
    {
        let checkmarkShapePath = UIBezierPath()
        checkmarkShapePath.move(to: CGPoint(x: 73.25, y: 14.05))
        checkmarkShapePath.addCurve(to: CGPoint(x: 64.51, y: 13.86), controlPoint1: CGPoint(x: 70.98, y: 11.44), controlPoint2: CGPoint(x: 66.78, y: 11.26))
        checkmarkShapePath.addLine(to: CGPoint(x: 27.46, y: 52))
        checkmarkShapePath.addLine(to: CGPoint(x: 15.75, y: 39.54))
        checkmarkShapePath.addCurve(to: CGPoint(x: 6.84, y: 39.54), controlPoint1: CGPoint(x: 13.48, y: 36.93), controlPoint2: CGPoint(x: 9.28, y: 36.93))
        checkmarkShapePath.addCurve(to: CGPoint(x: 6.84, y: 49.02), controlPoint1: CGPoint(x: 4.39, y: 42.14), controlPoint2: CGPoint(x: 4.39, y: 46.42))
        checkmarkShapePath.addLine(to: CGPoint(x: 22.91, y: 66.14))
        checkmarkShapePath.addCurve(to: CGPoint(x: 27.28, y: 68), controlPoint1: CGPoint(x: 24.14, y: 67.44), controlPoint2: CGPoint(x: 25.71, y: 68))
        checkmarkShapePath.addCurve(to: CGPoint(x: 31.65, y: 66.14), controlPoint1: CGPoint(x: 28.86, y: 68), controlPoint2: CGPoint(x: 30.43, y: 67.26))
        checkmarkShapePath.addLine(to: CGPoint(x: 73.08, y: 23.35))
        checkmarkShapePath.addCurve(to: CGPoint(x: 73.25, y: 14.05), controlPoint1: CGPoint(x: 75.52, y: 20.75), controlPoint2: CGPoint(x: 75.7, y: 16.65))
        checkmarkShapePath.close()
        checkmarkShapePath.miterLimit = 4;
        UIColor.white.setFill()
        checkmarkShapePath.fill()
    }
    
    class func drawCross()
    {
        let crossShapePath = UIBezierPath()
        crossShapePath.move(to: CGPoint(x: 10, y: 70))
        crossShapePath.addLine(to: CGPoint(x: 70, y: 10))
        crossShapePath.move(to: CGPoint(x: 10, y: 10))
        crossShapePath.addLine(to: CGPoint(x: 70, y: 70))
        crossShapePath.lineCapStyle = CGLineCap.round;
        crossShapePath.lineJoinStyle = CGLineJoin.round;
        UIColor.white.setStroke()
        crossShapePath.lineWidth = 14
        crossShapePath.stroke()
    }
    
    class func drawWarning()
    {
        let greyColor = UIColor(red: 0.236, green: 0.236, blue: 0.236, alpha: 1.000)

        let warningCirclePath = UIBezierPath()
        warningCirclePath.move(to: CGPoint(x: 40.94, y: 63.39))
        warningCirclePath.addCurve(to: CGPoint(x: 36.03, y: 65.55), controlPoint1: CGPoint(x: 39.06, y: 63.39), controlPoint2: CGPoint(x: 37.36, y: 64.18))
        warningCirclePath.addCurve(to: CGPoint(x: 34.14, y: 70.45), controlPoint1: CGPoint(x: 34.9, y: 66.92), controlPoint2: CGPoint(x: 34.14, y: 68.49))
        warningCirclePath.addCurve(to: CGPoint(x: 36.22, y: 75.54), controlPoint1: CGPoint(x: 34.14, y: 72.41), controlPoint2: CGPoint(x: 34.9, y: 74.17))
        warningCirclePath.addCurve(to: CGPoint(x: 40.94, y: 77.5), controlPoint1: CGPoint(x: 37.54, y: 76.91), controlPoint2: CGPoint(x: 39.06, y: 77.5))
        warningCirclePath.addCurve(to: CGPoint(x: 45.86, y: 75.35), controlPoint1: CGPoint(x: 42.83, y: 77.5), controlPoint2: CGPoint(x: 44.53, y: 76.72))
        warningCirclePath.addCurve(to: CGPoint(x: 47.93, y: 70.45), controlPoint1: CGPoint(x: 47.18, y: 74.17), controlPoint2: CGPoint(x: 47.93, y: 72.41))
        warningCirclePath.addCurve(to: CGPoint(x: 45.86, y: 65.35), controlPoint1: CGPoint(x: 47.93, y: 68.49), controlPoint2: CGPoint(x: 47.18, y: 66.72))
        warningCirclePath.addCurve(to: CGPoint(x: 40.94, y: 63.39), controlPoint1: CGPoint(x: 44.53, y: 64.18), controlPoint2: CGPoint(x: 42.83, y: 63.39))
        warningCirclePath.close()
        warningCirclePath.miterLimit = 4;
        
        greyColor.setFill()
        warningCirclePath.fill()
        
        
        // Warning Shape Drawing
        let warningShapePath = UIBezierPath()
        warningShapePath.move(to: CGPoint(x: 46.23, y: 4.26))
        warningShapePath.addCurve(to: CGPoint(x: 40.94, y: 2.5), controlPoint1: CGPoint(x: 44.91, y: 3.09), controlPoint2: CGPoint(x: 43.02, y: 2.5))
        warningShapePath.addCurve(to: CGPoint(x: 34.71, y: 4.26), controlPoint1: CGPoint(x: 38.68, y: 2.5), controlPoint2: CGPoint(x: 36.03, y: 3.09))
        warningShapePath.addCurve(to: CGPoint(x: 31.5, y: 8.77), controlPoint1: CGPoint(x: 33.01, y: 5.44), controlPoint2: CGPoint(x: 31.5, y: 7.01))
        warningShapePath.addLine(to: CGPoint(x: 31.5, y: 19.36))
        warningShapePath.addLine(to: CGPoint(x: 34.71, y: 54.44))
        warningShapePath.addCurve(to: CGPoint(x: 40.38, y: 58.16), controlPoint1: CGPoint(x: 34.9, y: 56.2), controlPoint2: CGPoint(x: 36.41, y: 58.16))
        warningShapePath.addCurve(to: CGPoint(x: 45.67, y: 54.44), controlPoint1: CGPoint(x: 44.34, y: 58.16), controlPoint2: CGPoint(x: 45.67, y: 56.01))
        warningShapePath.addLine(to: CGPoint(x: 48.5, y: 19.36))
        warningShapePath.addLine(to: CGPoint(x: 48.5, y: 8.77))
        warningShapePath.addCurve(to: CGPoint(x: 46.23, y: 4.26), controlPoint1: CGPoint(x: 48.5, y: 7.01), controlPoint2: CGPoint(x: 47.74, y: 5.44))
        warningShapePath.close()
        warningShapePath.miterLimit = 4;
        
        greyColor.setFill()
        warningShapePath.fill()
    }
    
    class func drawInfo()
    {
        // Color Declarations
        let color0 = UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.000)
        
        // Info Shape Drawing
        let infoShapePath = UIBezierPath()
        infoShapePath.move(to: CGPoint(x: 45.66, y: 15.96))
        infoShapePath.addCurve(to: CGPoint(x: 45.66, y: 5.22), controlPoint1: CGPoint(x: 48.78, y: 12.99), controlPoint2: CGPoint(x: 48.78, y: 8.19))
        infoShapePath.addCurve(to: CGPoint(x: 34.34, y: 5.22), controlPoint1: CGPoint(x: 42.53, y: 2.26), controlPoint2: CGPoint(x: 37.47, y: 2.26))
        infoShapePath.addCurve(to: CGPoint(x: 34.34, y: 15.96), controlPoint1: CGPoint(x: 31.22, y: 8.19), controlPoint2: CGPoint(x: 31.22, y: 12.99))
        infoShapePath.addCurve(to: CGPoint(x: 45.66, y: 15.96), controlPoint1: CGPoint(x: 37.47, y: 18.92), controlPoint2: CGPoint(x: 42.53, y: 18.92))
        infoShapePath.close()
        infoShapePath.move(to: CGPoint(x: 48, y: 69.41))
        infoShapePath.addCurve(to: CGPoint(x: 40, y: 77), controlPoint1: CGPoint(x: 48, y: 73.58), controlPoint2: CGPoint(x: 44.4, y: 77))
        infoShapePath.addLine(to: CGPoint(x: 40, y: 77))
        infoShapePath.addCurve(to: CGPoint(x: 32, y: 69.41), controlPoint1: CGPoint(x: 35.6, y: 77), controlPoint2: CGPoint(x: 32, y: 73.58))
        infoShapePath.addLine(to: CGPoint(x: 32, y: 35.26))
        infoShapePath.addCurve(to: CGPoint(x: 40, y: 27.67), controlPoint1: CGPoint(x: 32, y: 31.08), controlPoint2: CGPoint(x: 35.6, y: 27.67))
        infoShapePath.addLine(to: CGPoint(x: 40, y: 27.67))
        infoShapePath.addCurve(to: CGPoint(x: 48, y: 35.26), controlPoint1: CGPoint(x: 44.4, y: 27.67), controlPoint2: CGPoint(x: 48, y: 31.08))
        infoShapePath.addLine(to: CGPoint(x: 48, y: 69.41))
        infoShapePath.close()
        color0.setFill()
        infoShapePath.fill()
    }
    
    class func drawEdit()
    {
        // Color Declarations
        let color = UIColor(red:1.0, green:1.0, blue:1.0, alpha:1.0)
        
        // Edit shape Drawing
        let editPathPath = UIBezierPath()
        editPathPath.move(to: CGPoint(x: 71, y: 2.7))
        editPathPath.addCurve(to: CGPoint(x: 71.9, y: 15.2), controlPoint1: CGPoint(x: 74.7, y: 5.9), controlPoint2: CGPoint(x: 75.1, y: 11.6))
        editPathPath.addLine(to: CGPoint(x: 64.5, y: 23.7))
        editPathPath.addLine(to: CGPoint(x: 49.9, y: 11.1))
        editPathPath.addLine(to: CGPoint(x: 57.3, y: 2.6))
        editPathPath.addCurve(to: CGPoint(x: 69.7, y: 1.7), controlPoint1: CGPoint(x: 60.4, y: -1.1), controlPoint2: CGPoint(x: 66.1, y: -1.5))
        editPathPath.addLine(to: CGPoint(x: 71, y: 2.7))
        editPathPath.addLine(to: CGPoint(x: 71, y: 2.7))
        editPathPath.close()
        editPathPath.move(to: CGPoint(x: 47.8, y: 13.5))
        editPathPath.addLine(to: CGPoint(x: 13.4, y: 53.1))
        editPathPath.addLine(to: CGPoint(x: 15.7, y: 55.1))
        editPathPath.addLine(to: CGPoint(x: 50.1, y: 15.5))
        editPathPath.addLine(to: CGPoint(x: 47.8, y: 13.5))
        editPathPath.addLine(to: CGPoint(x: 47.8, y: 13.5))
        editPathPath.close()
        editPathPath.move(to: CGPoint(x: 17.7, y: 56.7))
        editPathPath.addLine(to: CGPoint(x: 23.8, y: 62.2))
        editPathPath.addLine(to: CGPoint(x: 58.2, y: 22.6))
        editPathPath.addLine(to: CGPoint(x: 52, y: 17.1))
        editPathPath.addLine(to: CGPoint(x: 17.7, y: 56.7))
        editPathPath.addLine(to: CGPoint(x: 17.7, y: 56.7))
        editPathPath.close()
        editPathPath.move(to: CGPoint(x: 25.8, y: 63.8))
        editPathPath.addLine(to: CGPoint(x: 60.1, y: 24.2))
        editPathPath.addLine(to: CGPoint(x: 62.3, y: 26.1))
        editPathPath.addLine(to: CGPoint(x: 28.1, y: 65.7))
        editPathPath.addLine(to: CGPoint(x: 25.8, y: 63.8))
        editPathPath.addLine(to: CGPoint(x: 25.8, y: 63.8))
        editPathPath.close()
        editPathPath.move(to: CGPoint(x: 25.9, y: 68.1))
        editPathPath.addLine(to: CGPoint(x: 4.2, y: 79.5))
        editPathPath.addLine(to: CGPoint(x: 11.3, y: 55.5))
        editPathPath.addLine(to: CGPoint(x: 25.9, y: 68.1))
        editPathPath.close()
        editPathPath.miterLimit = 4;
        editPathPath.usesEvenOddFillRule = true;
        color.setFill()
        editPathPath.fill()
    }
    
    // Generated Images
    class var imageOfCheckmark: UIImage {
        
        if Cache.imageOfCheckmark != nil
        {
            return Cache.imageOfCheckmark!
        }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 80, height: 80), false, 0)
        SwiftyAlertViewStyleKit.drawCheckmark()
        Cache.imageOfCheckmark = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return Cache.imageOfCheckmark!
    }
    
    class var imageOfCross: UIImage {
        
        if Cache.imageOfCross != nil
        {
            return Cache.imageOfCross!
        }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 80, height: 80), false, 0)
        SwiftyAlertViewStyleKit.drawCross()
        Cache.imageOfCross = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return Cache.imageOfCross!
    }
    
    class var imageOfWarning: UIImage {
        
        if Cache.imageOfWarning != nil
        {
            return Cache.imageOfWarning!
        }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 80, height: 80), false, 0)
        SwiftyAlertViewStyleKit.drawWarning()
        Cache.imageOfWarning = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return Cache.imageOfWarning!
    }
    
    class var imageOfInfo: UIImage {
        
        if Cache.imageOfInfo != nil
        {
            return Cache.imageOfInfo!
        }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 80, height: 80), false, 0)
        SwiftyAlertViewStyleKit.drawInfo()
        Cache.imageOfInfo = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return Cache.imageOfInfo!
    }
    
    class var imageOfEdit: UIImage {
        
        if Cache.imageOfEdit != nil
        {
            return Cache.imageOfEdit!
        }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 80, height: 80), false, 0)
        SwiftyAlertViewStyleKit.drawEdit()
        Cache.imageOfEdit = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return Cache.imageOfEdit!
    }
}

fileprivate extension String
{
    func heightWithConstrainedWidth(width: CGFloat, font: UIFont) -> CGFloat
    {
        let constraintRect = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(with: constraintRect, options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)
        return boundingBox.height
    }
}
