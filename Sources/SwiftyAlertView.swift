//
//  SwiftyAlertView.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/30/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

public import UIKit

@MainActor
open class SwiftyAlertButton: UIButton {
  /// 可选而非隐式解包:hideView() 收尾时会把它清空,而同一个实例再次 showTitle
  /// 时重新上屏的正是这些按钮 —— 隐式解包的调用会在那次点击上 trap。
  var action: (() -> Void)?

  /// 视觉高度是 35pt(见 layoutContents(in:)),低于 44×44pt 的最小点击目标。
  /// 这里只把**命中区域**对称扩到至少 44pt,不改视觉:竖排相邻按钮间隔 10pt,
  /// 上下各扩 4.5pt 不会与邻居重叠。
  open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    minimumHitTargetContains(point)
  }
}

/// addTextField() 实际返回的类型。视觉高度是 30pt(见 layoutContents(in:)),
/// 与按钮同理只把命中区域扩到至少 44pt:文本框之间间隔 15pt,上下各扩 7pt 不会重叠。
final class SwiftyAlertTextField: UITextField {
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    minimumHitTargetContains(point)
  }
}

extension UIView {
  /// 以 bounds 为中心、对称扩到至少 44×44pt 之后的区域是否包含 point。
  fileprivate func minimumHitTargetContains(_ point: CGPoint) -> Bool {
    let minimum: CGFloat = 44
    let dx = min(0, (bounds.width - minimum) / 2)
    let dy = min(0, (bounds.height - minimum) / 2)
    return bounds.insetBy(dx: dx, dy: dy).contains(point)
  }
}

// Allow alerts to be closed/renamed in a chainable manner
// Example: SwiftyAlertView.create().showSuccess("Test", subTitle: "Value").close()
@MainActor
public final class SwiftyAlertViewResponder {
  let alertview: SwiftyAlertView

  // Initialisation and Title/Subtitle/Close functions
  public init(alertview: SwiftyAlertView) {
    self.alertview = alertview
  }

  // 标题与副标题的高度都在布局时按当时的文本算,改完文本必须请求重新布局,
  // 否则上屏后换成更长的文本会溢出原来的框。
  public func setTitle(_ title: String) {
    self.alertview.labelTitle.text = title
    self.alertview.view.setNeedsLayout()
  }

  public func setSubTitle(_ subTitle: String) {
    self.alertview.viewText.text = subTitle
    self.alertview.view.setNeedsLayout()
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

// The Main Class
@MainActor
public final class SwiftyAlertView: UIViewController {

  let appearance: SwiftyAppearance

  // UI Colour
  var viewColor = UIColor()

  // UI Options
  public var iconTintColor: UIColor?

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
  /// 当前是否处于"已上屏、尚未开始收起"的状态。showTitle 的成功分支置 true,
  /// hideView() 一开始就置 false —— 它据此保证 dismissBlock 每次上屏只回调一次。
  /// internal 而非 private:单元测试进程没有 key window,走不到 showTitle 的成功分支,
  /// 测试直接置位来模拟"已上屏"(与 addKeyboardObservers() 开放给测试同一个理由)。
  var isPresented = false

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
    // 模态遮罩:VoiceOver 焦点不应跑到被遮住的内容上。
    view.accessibilityViewIsModal = true
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
    layoutContents(in: rv.frame.size)
  }

  /// 按给定的容器尺寸摆放 alert 的全部子视图。
  ///
  /// 从 viewWillLayoutSubviews 里拆出来,只为让单元测试能直接喂一个尺寸:测试进程
  /// 没有 window scene,viewWillLayoutSubviews 在 keyWindow 守卫处就返回了,
  /// 布局算术原本完全测不到。internal,对外不可见。
  func layoutContents(in sz: CGSize) {
    // Set background frame
    view.frame.size = sz

    let hMargin: CGFloat = 12
    let defaultTopOffset: CGFloat = 32

    // get actual height of title text
    var titleActualHeight: CGFloat = 0
    if let title = labelTitle.text {
      let textHeight = title.heightWithConstrainedWidth(
        width: appearance.kWindowWidth - hMargin * 2, font: labelTitle.font)
      // label 自己的高度也按当前文本重算(与 showTitle 里的算法相同)。它曾经只在
      // showTitle 里设过一次,经 responder 换成更长的标题后,重新布局也还是旧高度。
      labelTitle.frame.size.height = textHeight
      titleActualHeight = textHeight + 10
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

    let suggestedViewTextSize = viewText.sizeThatFits(
      CGSize(width: viewTextWidth, height: CGFloat.greatestFiniteMagnitude))
    let viewTextHeight = min(suggestedViewTextSize.height, maxViewTextHeight)

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

    // Subtitle
    y = titleActualHeight > 0 ? appearance.kTitleTop + titleActualHeight : defaultTopOffset
    viewText.frame = CGRect(x: hMargin, y: y, width: viewTextWidth, height: viewTextHeight)
    // Text fields
    y += viewTextHeight + 14.0
    for txt in inputs {
      txt.frame = CGRect(x: hMargin, y: y, width: appearance.kWindowWidth - hMargin * 2, height: 30)
      txt.layer.cornerRadius = appearance.fieldCornerRadius
      y += appearance.kTextFieldHeight
    }
    for txt in input {
      txt.frame = CGRect(
        x: hMargin, y: y, width: appearance.kWindowWidth - hMargin * 2,
        height: appearance.kTextViewdHeight - hMargin)
      y += appearance.kTextViewdHeight
    }
    // Buttons
    let numberOfButton = CGFloat(buttons.count)
    let buttonSpacing: CGFloat = 10
    let totalSpacing = numberOfButton >= 1 ? buttonSpacing * (numberOfButton - 1) : 0
    let widthEachButton = (appearance.kWindowWidth - 24 - totalSpacing) / numberOfButton
    var buttonX = CGFloat(12)

    switch appearance.buttonsLayout {
    case .vertical:
      for btn in buttons {
        btn.frame = CGRect(x: 12, y: y, width: appearance.kWindowWidth - 24, height: 35)
        btn.layer.cornerRadius = appearance.buttonCornerRadius
        y += appearance.kButtonHeight
      }
    case .horizontal:
      for btn in buttons {
        btn.frame = CGRect(x: buttonX, y: y, width: widthEachButton, height: 35)
        btn.layer.cornerRadius = appearance.buttonCornerRadius
        // 每个按钮之后只加**一个**间距;曾经加的是总间距,三个按钮起最后一个越界。
        buttonX += widthEachButton + buttonSpacing
      }
    }
  }

  var tmpContentViewFrameOrigin: CGPoint?
  var tmpCircleViewFrameOrigin: CGPoint?
  var keyboardHasBeenShown: Bool = false

  // NotificationCenter 的 block 形式注册,观察者是 addObserver 返回的 token,
  // self 从未被注册 —— removeObserver(self, name:) 对它们是彻头彻尾的空操作(B21)。
  // 必须把 token 存下来,再逐个 removeObserver(token)。写法照抄
  // SwiftyThreadPool.memoryWarningObserver(声明、init 里注册、deinit 里按 token 撤销)
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
      // 这里先在闭包自身的隔离域内取出唯一需要的值(CGRect 是 Sendable)。
      let keyboardEndFrame =
        (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
        .cgRectValue

      MainActor.assumeIsolated {
        guard let strongSelf = self else { return }
        // 注意顺序:即使拿不到键盘 frame,也要先把标志置位(沿用原行为)
        strongSelf.keyboardHasBeenShown = true
        guard let keyboardEndFrame else { return }

        // 键盘 frame 是屏幕坐标,contentView / circleBG 的 frame 在 baseView 的坐标系里。
        // 两者只在窗口铺满屏幕时才重合 —— iPad 分屏、台前调度下都不成立,必须先换算。
        // 不在窗口里时无从换算,沿用原值。
        let endKeyBoardFrame: CGFloat
        if let screenSpace = strongSelf.baseView.window?.screen.coordinateSpace {
          endKeyBoardFrame = strongSelf.baseView.convert(keyboardEndFrame, from: screenSpace).minY
        } else {
          endKeyBoardFrame = keyboardEndFrame.minY
        }

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
    super.touchesEnded(touches, with: event)
  }

  public func addTextField(_ title: String? = nil) -> UITextField {
    // Add text field
    let txt = SwiftyAlertTextField()
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
    btn.action?()
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

  // showSuccess(title, subTitle)
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

  // showError(title, subTitle)
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

  // showWarning(title, subTitle)
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

  // showInfo(title, subTitle)
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

  // showTitle(title, subTitle, style)
  //
  // colorStyle 默认 nil,即取 style.defaultColorInt。它曾默认为 0x000000:
  // `?? style.defaultColorInt` 只在显式传 nil 时才生效,直接调 showTitle(…, style: .success)
  // 得到的是黑色圆圈和按钮。
  @discardableResult
  public func showTitle(
    _ title: String, subTitle: String, style: SwiftyAlertViewStyle, colorStyle: UInt? = nil,
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
    // 参照 SwiftyToast.show() 里同一形状的 `guard let window` 守卫:提前返回前先把
    // 自身的残留引用交代干净。
    guard let rv = SwiftyGlobal.keyWindow else {
      // 无可用窗口时不展示,仍返回 responder 以维持签名。
      // 这条分支不注册键盘观察者(注册在守卫之后),因此不需要配平 ——
      // 注册与撤销在每一条出口上都成对:走到这里 = 从未注册。
      return SwiftyAlertViewResponder(alertview: self)
    }
    selfReference = self
    isPresented = true
    // 展示开始,挂上键盘观察者;由 hideView() 撤销。两者构成本类型显式的
    // 展示生命周期,详见 addKeyboardObservers() 的说明。
    addKeyboardObservers()
    rv.addSubview(view)
    view.frame = rv.bounds
    baseView.frame = rv.bounds

    // Alert colour/icon
    viewColor = UIColor.hex(colorStyle ?? style.defaultColorInt)

    // Icon style
    let defaultIcon: UIImage
    switch style {
    case .success: defaultIcon = SwiftyAlertViewStyleKit.imageOfCheckmark
    case .error: defaultIcon = SwiftyAlertViewStyleKit.imageOfCross
    case .warning: defaultIcon = SwiftyAlertViewStyleKit.imageOfWarning
    case .info: defaultIcon = SwiftyAlertViewStyleKit.imageOfInfo
    case .edit: defaultIcon = SwiftyAlertViewStyleKit.imageOfEdit
    }
    let iconImage = checkCircleIconImage(circleIconImage, defaultImage: defaultIcon)

    // Title
    if !title.isEmpty {
      self.labelTitle.text = title
      let actualHeight = title.heightWithConstrainedWidth(
        width: appearance.kWindowWidth - 24, font: self.labelTitle.font)
      self.labelTitle.frame = CGRect(
        x: 12, y: appearance.kTitleTop, width: appearance.kWindowWidth - 24, height: actualHeight)
    }

    // Subtitle
    // 副标题框的尺寸在 layoutContents(in:) 里按内容算,这里只设文本。
    if !subTitle.isEmpty {
      viewText.text = subTitle
    }

    //hidden/show circular view based on the ui option
    circleView.isHidden = !appearance.showCircularIcon
    circleBG.isHidden = !appearance.showCircularIcon

    // Alert view colour and images
    circleView.backgroundColor = viewColor

    let iconView = UIImageView(
      image: iconTintColor == nil ? iconImage : iconImage.withRenderingMode(.alwaysTemplate))
    iconView.tintColor = iconTintColor
    circleIconView = iconView

    circleView.addSubview(iconView)
    let x = (appearance.kCircleHeight - appearance.kCircleIconHeight) / 2
    iconView.frame = CGRect(
      x: x, y: x, width: appearance.kCircleIconHeight, height: appearance.kCircleIconHeight)
    iconView.layer.masksToBounds = true

    for txt in inputs {
      txt.layer.borderColor = viewColor.cgColor
    }

    for txt in input {
      txt.layer.borderColor = viewColor.cgColor
    }

    for btn in buttons {
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

  // Close SwiftyAlertView
  @objc
  public func hideView() {
    // 与 showTitle 的 addKeyboardObservers() 配对。放在动画**之前**而不是完成
    // 回调里:一旦决定收起,就不该再让键盘通知挪动这个 alert;而且即便动画的
    // 完成回调因故没跑到,撤销也已经发生 —— 注册与撤销必须在每条路径上成对。
    // 可重复调用,重复 hideView() 是安全的。
    removeKeyboardObservers()

    // 从未上屏(无窗口时 showTitle 提前返回),或已经在收起:到此为止。
    // 否则 dismissBlock 会为一次根本没发生的展示回调,或为一次收起回调两次。
    guard isPresented else { return }
    isPresented = false

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
        for button in self.buttons {
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
      for view in subviews {
        if view.tag == uniqueTag && view.accessibilityIdentifier == uniqueAccessibilityIdentifier {
          return true
        }
      }
    }
    return false
  }
}
