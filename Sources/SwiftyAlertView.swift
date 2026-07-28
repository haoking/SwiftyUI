//
//  SwiftyAlertView.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/30/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

@MainActor
open class SwiftyAlertButton: UIButton {
  var action: (() -> Void)!
}

// Allow alerts to be closed/renamed in a chainable manner
// Example: SwiftyAlertView().showSuccess(self, title: "Test", subTitle: "Value").close()
@MainActor
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
@MainActor
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
    // 与本文件其余取屏位置(viewWillLayoutSubviews / showTitle / showAnimation /
    // isShowing)保持一致,从 key window 取尺寸而不是 UIScreen.main:
    // UIScreen.main 自 iOS 16 起废弃,且在多窗口 / 分屏 / Stage Manager 下返回的是
    // 整块物理屏幕,而不是本 alert 真正所在的那个窗口 —— 与已修的 B17、B1 同一缺陷类。
    // 今天不报废弃告警只是因为部署目标是 iOS 15(低于废弃版本),抬高目标即会暴露。
    // 无窗口时取 .zero:这里只是初始值,真正的布局在 viewWillLayoutSubviews 里
    // 按当时的 key window 重算。
    view.frame = SwiftyGlobal.keyWindow?.bounds ?? .zero
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
    guard let rv = SwiftyGlobal.keyWindow else { return }
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

  // NotificationCenter 的 block 形式注册,观察者是 addObserver 返回的 token,
  // self 从未被注册 —— removeObserver(self, name:) 对它们是彻头彻尾的空操作(B21)。
  // 必须把 token 存下来,再逐个 removeObserver(token)。写法照抄
  // SwiftyThreadPool.memoryWarningObserver(SwiftyThreadPool.swift:44/57/167)
  // 与 ImageCachePool.memoryWarningObserver,全库保持同一形状。
  private var keyboardWillShowObserver: (any NSObjectProtocol)?
  private var keyboardWillHideObserver: (any NSObjectProtocol)?

  /// 挂上两个键盘观察者。与 removeKeyboardObservers() 成对,由 showTitle /
  /// hideView 驱动。
  ///
  /// **为什么不是 viewDidAppear / viewDidDisappear**:不是因为它们不触发 ——
  /// 实测(iOS 26.5 模拟器)它们**会**触发:把注册搬回 viewDidAppear,
  /// `testAlertWithTextFieldAvoidsKeyboard` 照样通过。这一点值得写下来,因为
  /// 按经典 UIKit 规则,一个既不 present、也不做容器包含、更不是 window
  /// rootViewController 的控制器(showTitle 只是把 view 裸 `addSubview` 到
  /// window 上,见下方)不该收到外观回调 —— 规则如此,实际行为并非如此。
  ///
  /// 换站点的真正理由是**不去依赖这个没有契约保证的行为**,外加两条硬收益:
  ///
  /// 1. 与本类型自带的那套显式展示生命周期(showTitle 里的 selfReference 自持有、
  ///    hideView 里的清理)确定性配对。无 key window 的提前返回发生在注册之前,
  ///    因此"注册与撤销在每条出口上成对"这条不变量在所有路径上都成立。
  /// 2. hideView() 在动画**之前**撤销:一旦决定收起,迟到的键盘通知就不该再挪动
  ///    这个正在消失的 alert。挂在 viewDidDisappear 上做不到这件事 —— 那时动画
  ///    早就跑完了。
  ///
  /// 不改上屏方式(那是另一回事,风险大得多且这里并不需要)。
  ///
  /// internal 而非 private:单元测试进程没有任何 window scene
  /// (`UIApplication.shared.connectedScenes` 为空),`SwiftyGlobal.keyWindow`
  /// 恒为 nil,showTitle 的成功分支在测试里根本走不到。开放到 internal 以便
  /// 测试直接驱动这一对方法。对外仍不可见。
  ///
  /// 下面两处 MainActor.assumeIsolated **不是**过渡代码,不要当成 2.0 迁移期
  /// 遗留的桥接顺手删掉。它们跨的是一条真实且长期存在的边界:
  /// NotificationCenter 的 block 形式接口收的是 `@Sendable (Notification) -> Void`
  /// ——一个非隔离闭包,类型系统里没有办法声明"它只会在主线程被调用"。
  /// 而 queue: nil 表示在**发送方线程**同步回调,键盘通知恒由 UIKit 在主线程发出,
  /// 所以断言成立;改成 Task 跳回主 actor 会把同步的帧调整变成异步,键盘弹出时
  /// 会看到明显的跳动。assumeIsolated 在假设被违反时会 trap,是受检断言而非掩盖。
  func addKeyboardObservers() {
    // 先撤销上一轮的注册再重新注册:同一个实例可能被再次 showTitle,
    // 不先撤销就会用新 token 覆盖旧 token,旧观察者从此永远失去被移除的机会
    // —— 那正是 B21 的泄漏形态,只是换了个入口。
    removeKeyboardObservers()

    keyboardWillShowObserver = NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil
    ) { [weak self] (notification) in
      // Notification 不是 Sendable,不能整个送进 assumeIsolated;
      // 这里先在闭包自身的隔离域内取出唯一需要的标量(CGFloat 是 Sendable)。
      let endKeyBoardFrameY =
        (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
        .cgRectValue.minY

      MainActor.assumeIsolated {
        guard let strongSelf = self else { return }
        // 注意顺序:即使拿不到键盘 frame,也要先把标志置位(沿用原行为)
        strongSelf.keyboardHasBeenShown = true
        guard let endKeyBoardFrame = endKeyBoardFrameY else { return }

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
    }

    // 键盘收起:把上面那个观察者保存下来的原始 origin 还原回去。
    // 2.0 之前这里错注册在 keyboardWillShowNotification 上,与上面那个观察者
    // **同注册在一个通知**上:按注册顺序,上面刚把 alert 上移,这里紧接着就在
    // 同一次派发里把 origin 还原并清空,每次键盘弹出的净效果恒为零 —— 也就是说
    // 键盘避让功能整体失效,而 addTextField() 存在的意义正是配合键盘(B20)。
    keyboardWillHideObserver = NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil
    ) { [weak self] (_) in
      MainActor.assumeIsolated {
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
  }

  /// 撤销两个键盘观察者,并清掉它们留下的簿记。可重复调用:token 撤销后立刻置 nil。
  ///
  /// 之所以必须按 token 撤销而不是 `removeObserver(self, name:)`:见上方
  /// keyboardWillShowObserver 的说明(B21)。观察者只持 `[weak self]`,所以
  /// 控制器本身能正常释放 —— 泄漏的是 NotificationCenter 里的注册项本身:
  /// 每展示一次 alert 就多两个,进程生命周期内只增不减,且每次键盘事件都会
  /// 把它们**全部**触发一遍。这与两个 block 内的 MainActor.assumeIsolated 复合
  /// 更糟:后台线程 post 键盘通知会 trap,而 trap 点数量随展示次数单调增长。
  ///
  /// **为什么这里要顺手清 tmp*FrameOrigin 与 keyboardHasBeenShown**:
  /// 这三个字段是显示观察者写、隐藏观察者清的一份中间状态,它们和这两个 token
  /// 是同一份状态的两半。而 hideView() 把撤销提到了消失动画**之前**(见那里的
  /// 说明),于是"键盘还弹着就关掉 alert"这条路径上,隐藏观察者在键盘真正收起
  /// 之前就已经被撤销 —— 它的清理永远不会发生,三个字段全部残留。
  /// 撤销走一半、留一半,等于把状态交给一个已经不存在的清理者。
  /// 在这里一并清掉,"注册/撤销不留残留"这条不变量才在每条路径上都成立。
  ///
  /// 只清簿记、不还原 frame 是有意的:走到这里要么是 alert 正在消失(还原一个
  /// 马上就要被移除的视图没有意义,还会和消失动画打架),要么是 addKeyboardObservers()
  /// 在重新注册前先清场(那时本就该从干净状态开始)。
  func removeKeyboardObservers() {
    if let observer = keyboardWillShowObserver {
      NotificationCenter.default.removeObserver(observer)
      keyboardWillShowObserver = nil
    }
    if let observer = keyboardWillHideObserver {
      NotificationCenter.default.removeObserver(observer)
      keyboardWillHideObserver = nil
    }
    tmpContentViewFrameOrigin = nil
    tmpCircleViewFrameOrigin = nil
    keyboardHasBeenShown = false
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
    view.alpha = 0
    view.tag = uniqueTag
    view.accessibilityIdentifier = uniqueAccessibilityIdentifier
    // keyWindow 守卫必须排在 selfReference = self **之前**。
    // selfReference 是展示期间的自持有(调用方不留引用,alert 也能活到 hideView()),
    // 而它只在 hideView() 的 completion 里被清空 —— 提前 return 的分支永远到不了那里。
    // 1.x 这条路径是 `UIApplication.shared.keyWindow!` 的无条件崩溃,泄漏因此不可能
    // 存在;加固 B1 时若照搬原来的语句顺序,等于把崩溃换成了永久泄漏。
    // 参照 SwiftyToast 同一形状的守卫(SwiftyToast.swift:80-83):提前返回前先把
    // 自身的残留引用交代干净。
    guard let rv = SwiftyGlobal.keyWindow else {
      // 无可用窗口时不展示,仍返回 responder 以维持签名。
      // 这条分支不注册键盘观察者(注册在守卫之后),因此不需要配平 ——
      // 注册与撤销在每一条出口上都成对:走到这里 = 从未注册。
      return SwiftyAlertViewResponder(alertview: self)
    }
    selfReference = self
    // 展示开始,挂上键盘观察者;由 hideView() 撤销。两者构成本类型显式的
    // 展示生命周期,详见 addKeyboardObservers() 的说明。
    addKeyboardObservers()
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
    guard let rv = SwiftyGlobal.keyWindow else { return }
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
    // 与 showTitle 的 addKeyboardObservers() 配对。放在动画**之前**而不是完成
    // 回调里:一旦决定收起,就不该再让键盘通知挪动这个 alert;而且即便动画的
    // 完成回调因故没跑到,撤销也已经发生 —— 注册与撤销必须在每条路径上成对。
    // 可重复调用,重复 hideView() 是安全的。
    removeKeyboardObservers()

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
    if let subviews = SwiftyGlobal.keyWindow?.subviews {
      for (_, view) in subviews.enumerated() {
        if view.tag == uniqueTag && view.accessibilityIdentifier == uniqueAccessibilityIdentifier {
          return true
        }
      }
    }
    return false
  }
}
