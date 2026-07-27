//
//  SwiftyAlert.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/30/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

open class SwiftyAlertButton: UIButton {
  var action: (() -> Void)!
}

// Allow alerts to be closed/renamed in a chainable manner
// Example: SwiftyAlertView().showSuccess(self, title: "Test", subTitle: "Value").close()
public final class SwiftyAlertViewResponder {
  let alertview: SwiftyAlertView

  // Initialisation and Title/Subtitle/Close functions
  public init(alertview: SwiftyAlertView) {
    self.alertview = alertview
  }

  public func setTitle(_ title: String) {
    self.alertview.labelTitle.text = title
  }

  public func setSubTitle(_ subTitle: String) {
    self.alertview.viewText.text = subTitle
  }

  public func close() {
    self.alertview.hideView()
  }

  public func setDismissBlock(_ dismissBlock: @escaping () -> Void) {
    self.alertview.dismissBlock = dismissBlock
  }
}

private let kCircleHeightBackground: CGFloat = 62.0
private let uniqueTag: Int = Int(arc4random() % UInt32(Int32.max))
private let uniqueAccessibilityIdentifier: String = "SwiftyAlert"

//public typealias DismissBlock = () -> Void

// The Main Class
//
// 未标注 @MainActor 的说明见 SwiftyLabel.swift"存储属性"一节;本类型与
// SwiftyAlertButton、SwiftyAlertViewResponder(同文件)一样,隔离标注
// 统一推迟到 Task 17。
public final class SwiftyAlertView: UIViewController {

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
  var circleBG = UIView(
    frame: CGRect(x: 0, y: 0, width: kCircleHeightBackground, height: kCircleHeightBackground))
  var circleView = UIView()
  var circleIconView: UIView?
  var dismissBlock: (() -> Void)?
  fileprivate var inputs = [UITextField]()
  fileprivate var input = [UITextView]()
  internal var buttons = [SwiftyAlertButton]()
  fileprivate var selfReference: SwiftyAlertView?

  private init(_ appearance: SwiftyAppearance) {
    self.appearance = appearance
    super.init(nibName: nil, bundle: nil)
    setup()
  }

  required public init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public final class func create(_ appearance: SwiftyAppearance = SwiftyAppearance())
    -> SwiftyAlertView
  {
    return SwiftyAlertView(appearance)
  }

  fileprivate func setup() {
    // Set up main view
    view.frame = UIScreen.main.bounds
    view.autoresizingMask = [
      UIView.AutoresizingMask.flexibleHeight, UIView.AutoresizingMask.flexibleWidth,
    ]
    view.backgroundColor = UIColor(
      red: 0, green: 0, blue: 0, alpha: appearance.kDefaultShadowOpacity)
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
    circleView.frame = CGRect(
      x: x, y: x + appearance.kCircleTopPosition, width: appearance.kCircleHeight,
      height: appearance.kCircleHeight)
    circleView.layer.cornerRadius = circleView.frame.size.height / 2
    // Title
    labelTitle.numberOfLines = 0
    labelTitle.textAlignment = .center
    labelTitle.font = appearance.kTitleFont
    if appearance.kTitleMinimumScaleFactor < 1 {
      labelTitle.minimumScaleFactor = appearance.kTitleMinimumScaleFactor
      labelTitle.adjustsFontSizeToFitWidth = true
    }
    labelTitle.frame = CGRect(
      x: 12, y: appearance.kTitleTop, width: appearance.kWindowWidth - 24,
      height: appearance.kTitleHeight)
    // View text
    viewText.isEditable = false
    viewText.isSelectable = false
    viewText.textAlignment = .center
    viewText.textContainerInset = UIEdgeInsets.zero
    viewText.textContainer.lineFragmentPadding = 0
    viewText.font = appearance.kTextFont
    // Colours
    contentView.backgroundColor = appearance.contentViewColor
    viewText.backgroundColor = appearance.contentViewColor
    labelTitle.textColor = appearance.titleColor
    viewText.textColor = appearance.titleColor
    contentView.layer.borderColor = appearance.contentViewBorderColor.cgColor
    //Gesture Recognizer for tapping outside the textinput
    if !appearance.disableTapGesture {
      let tapGesture = UITapGestureRecognizer(
        target: self, action: #selector(SwiftyAlertView.tapped(_:)))
      tapGesture.numberOfTapsRequired = 1
      self.view.addGestureRecognizer(tapGesture)
    }
  }

  override public func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    // SwiftyGlobal 是 @MainActor 隔离的,而 SwiftyAlertView 本身不是——隔离标注
    // 统一推迟到 Task 17(见 SwiftyLabel.swift"存储属性"一节的说明)。UIKit
    // 保证 viewWillLayoutSubviews 只在主线程调用,故此处 assumeIsolated 不会
    // trap;Task 17 加上 @MainActor 后,本桥接可整体删除。
    guard let rv = MainActor.assumeIsolated({ SwiftyGlobal.keyWindow }) else { return }
    let sz = rv.frame.size

    // Set background frame
    view.frame.size = sz

    let hMargin: CGFloat = 12
    let defaultTopOffset: CGFloat = 32

    // get actual height of title text
    var titleActualHeight: CGFloat = 0
    if let title = labelTitle.text {
      titleActualHeight =
        title.heightWithConstrainedWidth(
          width: appearance.kWindowWidth - hMargin * 2, font: labelTitle.font) + 10
      // get the larger height for the title text
      titleActualHeight =
        (titleActualHeight > appearance.kTitleHeight ? titleActualHeight : appearance.kTitleHeight)
    }

    // computing the right size to use for the textView
    let maxHeight = sz.height - 100  // max overall height
    var consumedHeight = CGFloat(0)
    consumedHeight +=
      (titleActualHeight > 0 ? appearance.kTitleTop + titleActualHeight : defaultTopOffset)
    consumedHeight += 14

    if appearance.buttonsLayout == .vertical {
      consumedHeight += appearance.kButtonHeight * CGFloat(buttons.count)
    } else {
      consumedHeight += appearance.kButtonHeight
    }
    consumedHeight += appearance.kTextFieldHeight * CGFloat(inputs.count)
    consumedHeight += appearance.kTextViewdHeight * CGFloat(input.count)
    let maxViewTextHeight = maxHeight - consumedHeight
    let viewTextWidth = appearance.kWindowWidth - hMargin * 2
    var viewTextHeight = appearance.kTextHeight

    let suggestedViewTextSize = viewText.sizeThatFits(
      CGSize(width: viewTextWidth, height: CGFloat.greatestFiniteMagnitude))
    viewTextHeight = min(suggestedViewTextSize.height, maxViewTextHeight)

    // scroll management
    if suggestedViewTextSize.height > maxViewTextHeight {
      viewText.isScrollEnabled = true
    } else {
      viewText.isScrollEnabled = false
    }

    let windowHeight = consumedHeight + viewTextHeight
    // Set frames
    var x = (sz.width - appearance.kWindowWidth) / 2
    var y = (sz.height - windowHeight - (appearance.kCircleHeight / 8)) / 2
    contentView.frame = CGRect(x: x, y: y, width: appearance.kWindowWidth, height: windowHeight)
    contentView.layer.cornerRadius = appearance.contentViewCornerRadius
    y -= kCircleHeightBackground * 0.6
    x = (sz.width - kCircleHeightBackground) / 2
    circleBG.frame = CGRect(
      x: x, y: y + appearance.kCircleBackgroundTopPosition, width: kCircleHeightBackground,
      height: kCircleHeightBackground)

    //adjust Title frame based on circularIcon show/hide flag
    //        let titleOffset : CGFloat = appearance.showCircularIcon ? 0.0 : -12.0
    let titleOffset: CGFloat = 0
    labelTitle.frame = labelTitle.frame.offsetBy(dx: 0, dy: titleOffset)

    // Subtitle
    y =
      titleActualHeight > 0
      ? appearance.kTitleTop + titleActualHeight + titleOffset : defaultTopOffset
    viewText.frame = CGRect(
      x: hMargin, y: y, width: appearance.kWindowWidth - hMargin * 2, height: appearance.kTextHeight
    )
    viewText.frame = CGRect(x: hMargin, y: y, width: viewTextWidth, height: viewTextHeight)
    // Text fields
    y += viewTextHeight + 14.0
    for (_, txt) in inputs.enumerated() {
      txt.frame = CGRect(x: hMargin, y: y, width: appearance.kWindowWidth - hMargin * 2, height: 30)
      txt.layer.cornerRadius = appearance.fieldCornerRadius
      y += appearance.kTextFieldHeight
    }
    for (_, txt) in input.enumerated() {
      txt.frame = CGRect(
        x: hMargin, y: y, width: appearance.kWindowWidth - hMargin * 2,
        height: appearance.kTextViewdHeight - hMargin)
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
      for (_, btn) in buttons.enumerated() {
        btn.frame = CGRect(x: 12, y: y, width: appearance.kWindowWidth - 24, height: 35)
        btn.layer.cornerRadius = appearance.buttonCornerRadius
        y += appearance.kButtonHeight
      }
    case .horizontal:
      for (_, btn) in buttons.enumerated() {
        btn.frame = CGRect(x: buttonX, y: y, width: widthEachButton, height: 35)
        btn.layer.cornerRadius = appearance.buttonCornerRadius
        buttonX += widthEachButton
        buttonX += buttonsSpace
      }
    }
  }

  var tmpContentViewFrameOrigin: CGPoint?
  var tmpCircleViewFrameOrigin: CGPoint?
  var keyboardHasBeenShown: Bool = false

  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil
    ) { [weak self] (notification) in

      guard let strongSelf = self else { return }
      strongSelf.keyboardHasBeenShown = true
      guard let userInfo = notification.userInfo else { return }
      guard
        let endKeyBoardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
          .cgRectValue.minY
      else { return }

      if strongSelf.tmpContentViewFrameOrigin == nil {
        strongSelf.tmpContentViewFrameOrigin = strongSelf.contentView.frame.origin
      }

      if strongSelf.tmpCircleViewFrameOrigin == nil {
        strongSelf.tmpCircleViewFrameOrigin = strongSelf.circleBG.frame.origin
      }

      var newContentViewFrameY = strongSelf.contentView.frame.maxY - endKeyBoardFrame
      if newContentViewFrameY < 0 {
        newContentViewFrameY = 0
      }

      let newBallViewFrameY = strongSelf.circleBG.frame.origin.y - newContentViewFrameY
      strongSelf.contentView.frame.origin.y -= newContentViewFrameY
      strongSelf.circleBG.frame.origin.y = newBallViewFrameY
    }

    NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil
    ) { [weak self] (notification) in

      guard let strongSelf = self else { return }
      if strongSelf.keyboardHasBeenShown {  //This could happen on the simulator (keyboard will be hidden)
        if strongSelf.tmpContentViewFrameOrigin != nil {
          strongSelf.contentView.frame.origin.y = strongSelf.tmpContentViewFrameOrigin!.y
          strongSelf.tmpContentViewFrameOrigin = nil
        }
        if strongSelf.tmpCircleViewFrameOrigin != nil {
          strongSelf.circleBG.frame.origin.y = strongSelf.tmpCircleViewFrameOrigin!.y
          strongSelf.tmpCircleViewFrameOrigin = nil
        }

        strongSelf.keyboardHasBeenShown = false
      }

    }
  }

  public override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    NotificationCenter.default.removeObserver(
      self, name: UIResponder.keyboardWillShowNotification, object: nil)
    NotificationCenter.default.removeObserver(
      self, name: UIResponder.keyboardWillHideNotification, object: nil)
  }

  override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if let count = event?.touches(for: view)?.count, count > 0 {
      view.endEditing(true)
    }
  }

  public func addTextField(_ title: String? = nil) -> UITextField {
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

  public func addTextView() -> UITextView {
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
  public func addButton(_ title: String, action: @escaping () -> Void) -> SwiftyAlertButton {
    appearance.setkWindowHeight(appearance.kWindowHeight + appearance.kButtonHeight)
    // Add button
    let btn = SwiftyAlertButton()
    btn.layer.masksToBounds = true
    btn.setTitle(title, for: UIControl.State())
    btn.titleLabel?.font = appearance.kButtonFont

    btn.action = action

    btn.addTarget(self, action: #selector(SwiftyAlertView.buttonTapped(_:)), for: .touchUpInside)
    btn.addTarget(
      self, action: #selector(SwiftyAlertView.buttonTapDown(_:)),
      for: [.touchDown, .touchDragEnter])
    btn.addTarget(
      self, action: #selector(SwiftyAlertView.buttonRelease(_:)),
      for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragOutside])

    contentView.addSubview(btn)
    buttons.append(btn)
    return btn
  }

  @objc
  func buttonTapped(_ btn: SwiftyAlertButton) {
    btn.action()
    if self.view.alpha != 0.0 && appearance.shouldAutoDismiss { hideView() }
  }

  @objc
  func buttonTapDown(_ btn: SwiftyAlertButton) {
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0
    let pressBrightnessFactor = 0.85
    btn.backgroundColor?.getHue(
      &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    brightness = brightness * CGFloat(pressBrightnessFactor)
    btn.backgroundColor = UIColor(
      hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
  }

  @objc
  func buttonRelease(_ btn: SwiftyAlertButton) {
    btn.backgroundColor = viewColor
  }

  //Dismiss keyboard when tapped outside textfield & close SwiftyAlertView when hideWhenBackgroundViewIsTapped
  @objc func tapped(_ gestureRecognizer: UITapGestureRecognizer) {
    self.view.endEditing(true)

    if let tappedView = gestureRecognizer.view,
      tappedView.hitTest(gestureRecognizer.location(in: tappedView), with: nil) == baseView
        && appearance.hideWhenBackgroundViewIsTapped
    {
      hideView()
    }
  }

  // showSuccess(view, title, subTitle)
  @discardableResult
  public func showSuccess(
    _ title: String, subTitle: String,
    colorStyle: UInt = SwiftyAlertViewStyle.success.defaultColorInt,
    colorTextButton: UInt = 0xFFFFFF, circleIconImage: UIImage? = nil
  ) -> SwiftyAlertViewResponder {
    return showTitle(
      title, subTitle: subTitle, style: .success, colorStyle: colorStyle,
      colorTextButton: colorTextButton, circleIconImage: circleIconImage)
  }

  // showError(view, title, subTitle)
  @discardableResult
  public func showError(
    _ title: String, subTitle: String,
    colorStyle: UInt = SwiftyAlertViewStyle.error.defaultColorInt, colorTextButton: UInt = 0xFFFFFF,
    circleIconImage: UIImage? = nil
  ) -> SwiftyAlertViewResponder {
    return showTitle(
      title, subTitle: subTitle, style: .error, colorStyle: colorStyle,
      colorTextButton: colorTextButton, circleIconImage: circleIconImage)
  }

  // showWarning(view, title, subTitle)
  @discardableResult
  public func showWarning(
    _ title: String, subTitle: String,
    colorStyle: UInt = SwiftyAlertViewStyle.warning.defaultColorInt,
    colorTextButton: UInt = 0x000000, circleIconImage: UIImage? = nil
  ) -> SwiftyAlertViewResponder {
    return showTitle(
      title, subTitle: subTitle, style: .warning, colorStyle: colorStyle,
      colorTextButton: colorTextButton, circleIconImage: circleIconImage)
  }

  // showInfo(view, title, subTitle)
  @discardableResult
  public func showInfo(
    _ title: String, subTitle: String, colorStyle: UInt = SwiftyAlertViewStyle.info.defaultColorInt,
    colorTextButton: UInt = 0xFFFFFF, circleIconImage: UIImage? = nil
  ) -> SwiftyAlertViewResponder {
    return showTitle(
      title, subTitle: subTitle, style: .info, colorStyle: colorStyle,
      colorTextButton: colorTextButton, circleIconImage: circleIconImage)
  }

  @discardableResult
  public func showEdit(
    _ title: String, subTitle: String, colorStyle: UInt = SwiftyAlertViewStyle.edit.defaultColorInt,
    colorTextButton: UInt = 0xFFFFFF, circleIconImage: UIImage? = nil
  ) -> SwiftyAlertViewResponder {
    return showTitle(
      title, subTitle: subTitle, style: .edit, colorStyle: colorStyle,
      colorTextButton: colorTextButton, circleIconImage: circleIconImage)
  }

  // showTitle(view, title, subTitle, timeout, style)
  @discardableResult
  public func showTitle(
    _ title: String, subTitle: String, style: SwiftyAlertViewStyle, colorStyle: UInt? = 0x000000,
    colorTextButton: UInt? = 0xFFFFFF, circleIconImage: UIImage? = nil
  ) -> SwiftyAlertViewResponder {
    selfReference = self
    view.alpha = 0
    view.tag = uniqueTag
    view.accessibilityIdentifier = uniqueAccessibilityIdentifier
    // 同 viewWillLayoutSubviews 的 assumeIsolated 桥接说明,Task 17 起可删除。
    guard let rv = MainActor.assumeIsolated({ SwiftyGlobal.keyWindow }) else {
      // 无可用窗口时不展示,仍返回 responder 以维持签名
      return SwiftyAlertViewResponder(alertview: self)
    }
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

      iconImage = checkCircleIconImage(
        circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfCheckmark)

    case .error:

      iconImage = checkCircleIconImage(
        circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfCross)

    case .warning:

      iconImage = checkCircleIconImage(
        circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfWarning)

    case .info:

      iconImage = checkCircleIconImage(
        circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfInfo)

    case .edit:

      iconImage = checkCircleIconImage(
        circleIconImage, defaultImage: SwiftyAlertViewStyleKit.imageOfEdit)

    }

    // Title
    if !title.isEmpty {
      self.labelTitle.text = title
      let actualHeight = title.heightWithConstrainedWidth(
        width: appearance.kWindowWidth - 24, font: self.labelTitle.font)
      self.labelTitle.frame = CGRect(
        x: 12, y: appearance.kTitleTop, width: appearance.kWindowWidth - 24, height: actualHeight)
    }

    // Subtitle
    if !subTitle.isEmpty {
      viewText.text = subTitle
      // Adjust text view size, if necessary
      let str = subTitle as NSString
      let attr = [NSAttributedString.Key.font: viewText.font ?? UIFont()]
      let sz = CGSize(width: appearance.kWindowWidth - 24, height: 90)
      let r = str.boundingRect(
        with: sz, options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: attr,
        context: nil)
      let ht = ceil(r.size.height)
      if ht < appearance.kTextHeight {
        appearance.kWindowHeight -= (appearance.kTextHeight - ht)
        appearance.setkTextHeight(ht)
      }
    }

    //hidden/show circular view based on the ui option
    circleView.isHidden = !appearance.showCircularIcon
    circleBG.isHidden = !appearance.showCircularIcon

    // Alert view colour and images
    circleView.backgroundColor = viewColor

    if let iconTintColor = iconTintColor {
      circleIconView = UIImageView(image: iconImage!.withRenderingMode(.alwaysTemplate))
      circleIconView?.tintColor = iconTintColor
    } else {
      circleIconView = UIImageView(image: iconImage!)
    }

    circleView.addSubview(circleIconView!)
    let x = (appearance.kCircleHeight - appearance.kCircleIconHeight) / 2
    circleIconView!.frame = CGRect(
      x: x, y: x, width: appearance.kCircleIconHeight, height: appearance.kCircleIconHeight)
    circleIconView?.layer.masksToBounds = true

    for (_, txt) in inputs.enumerated() {
      txt.layer.borderColor = viewColor.cgColor
    }

    for (_, txt) in input.enumerated() {
      txt.layer.borderColor = viewColor.cgColor
    }

    for (_, btn) in buttons.enumerated() {
      btn.backgroundColor = viewColor
      btn.setTitleColor(UIColor.hex(colorTextButton ?? 0xFFFFFF), for: UIControl.State())
    }

    // Animate in the alert view
    self.showAnimation()

    // Chainable objects
    return SwiftyAlertViewResponder(alertview: self)
  }

  // Show animation in the alert view
  fileprivate func showAnimation(
    animationStartOffset: CGFloat = -400.0, boundingAnimationOffset: CGFloat = 15.0,
    animationDuration: TimeInterval = 0.2
  ) {
    // 同 viewWillLayoutSubviews 的 assumeIsolated 桥接说明,Task 17 起可删除。
    guard let rv = MainActor.assumeIsolated({ SwiftyGlobal.keyWindow }) else { return }
    var animationStartOrigin = self.baseView.frame.origin
    var animationCenter: CGPoint = rv.center

    animationStartOrigin = CGPoint(
      x: animationStartOrigin.x, y: self.baseView.frame.origin.y + animationStartOffset)
    animationCenter = CGPoint(x: animationCenter.x, y: animationCenter.y + boundingAnimationOffset)

    self.baseView.frame.origin = animationStartOrigin

    UIView.animate(
      withDuration: animationDuration,
      animations: {
        self.view.alpha = 1.0
        self.baseView.center = animationCenter
      },
      completion: { finished in
        UIView.animate(
          withDuration: animationDuration,
          animations: {
            self.view.alpha = 1.0
            self.baseView.center = rv.center
          })
      })
  }

  // DynamicAnimator function
  var animator: UIDynamicAnimator?
  var snapBehavior: UISnapBehavior?

  fileprivate func animate(item: UIView, center: CGPoint) {
    if let snapBehavior = self.snapBehavior {
      self.animator?.removeBehavior(snapBehavior)
    }

    self.animator = UIDynamicAnimator.init(referenceView: self.view)
    let tempSnapBehavior = UISnapBehavior.init(item: item, snapTo: center)
    self.animator?.addBehavior(tempSnapBehavior)
    self.snapBehavior? = tempSnapBehavior
  }

  // Close SwiftyAlertView
  @objc
  public func hideView() {
    UIView.animate(
      withDuration: 0.2,
      animations: {
        self.view.alpha = 0
      },
      completion: { finished in

        if let dismissBlock = self.dismissBlock {
          dismissBlock()
        }

        // This is necessary for SwiftyAlertView to be de-initialized, preventing a strong reference cycle with the viewcontroller calling SwiftyAlertView.
        for (_, button) in self.buttons.enumerated() {
          button.action = nil
        }

        self.view.removeFromSuperview()
        self.selfReference = nil
      })
  }

  func checkCircleIconImage(_ circleIconImage: UIImage?, defaultImage: UIImage) -> UIImage {
    if let image = circleIconImage {
      return image
    } else {
      return defaultImage
    }
  }

  //Return true if a SwiftyAlertView is already being shown, false otherwise
  public func isShowing() -> Bool {
    // 同 viewWillLayoutSubviews 的 assumeIsolated 桥接说明,Task 17 起可删除。
    if let subviews = MainActor.assumeIsolated({ SwiftyGlobal.keyWindow })?.subviews {
      for (_, view) in subviews.enumerated() {
        if view.tag == uniqueTag && view.accessibilityIdentifier == uniqueAccessibilityIdentifier {
          return true
        }
      }
    }
    return false
  }
}
