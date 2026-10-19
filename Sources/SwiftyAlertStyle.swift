public import UIKit

public enum SwiftyAlertViewStyle {
  case success, error, warning, info, edit

  public var defaultColorInt: UInt {
    switch self {
    case .success:
      // 曾是 0x22B573:白字与白色对勾在它上面只有 2.65:1,低于 WCAG AA。
      // 0x198754 与白色为 4.53:1,文字(4.5:1)与图标(3:1)都达标。
      return 0x198754
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

public enum SwiftyAlertButtonLayout {
  case horizontal, vertical
}

// 跨文件为嵌套类型续体需要 extension,以保留 SwiftyAlertView.SwiftyAppearance 这一路径。
extension SwiftyAlertView {
  public struct SwiftyAppearance {
    let kDefaultShadowOpacity: CGFloat
    let kCircleTopPosition: CGFloat
    let kCircleBackgroundTopPosition: CGFloat
    let kCircleHeight: CGFloat
    let kCircleIconHeight: CGFloat
    let kTitleTop: CGFloat
    let kTitleHeight: CGFloat
    let kTitleMinimumScaleFactor: CGFloat
    let kWindowWidth: CGFloat
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
    var showCircularIcon: Bool
    var shouldAutoDismiss: Bool  // Set this false to 'Disable' Auto hideView when SwiftyAlertButton is tapped
    var contentViewCornerRadius: CGFloat
    var fieldCornerRadius: CGFloat
    var buttonCornerRadius: CGFloat
    var buttonsLayout: SwiftyAlertButtonLayout

    // Actions
    var hideWhenBackgroundViewIsTapped: Bool

    /// - Note: `kWindowHeight`、`kTextHeight` 与 `dynamicAnimatorActive` 不起作用:alert 的
    ///   整体高度与副标题框的高度都在布局时按内容计算(见 SwiftyAlertView.layoutContents(in:)),
    ///   动力学动画从未接线。这三个参数只为源码兼容而保留,下一个大版本移除。
    public init(
      kDefaultShadowOpacity: CGFloat = 0.7, kCircleTopPosition: CGFloat = 0.0,
      kCircleBackgroundTopPosition: CGFloat = 6.0, kCircleHeight: CGFloat = 56.0,
      kCircleIconHeight: CGFloat = 20.0, kTitleTop: CGFloat = 30.0, kTitleHeight: CGFloat = 25.0,
      kWindowWidth: CGFloat = 240.0, kWindowHeight: CGFloat = 178.0, kTextHeight: CGFloat = 90.0,
      kTextFieldHeight: CGFloat = 45.0, kTextViewdHeight: CGFloat = 80.0,
      kButtonHeight: CGFloat = 45.0, kTitleFont: UIFont = UIFont.systemFont(ofSize: 20),
      kTitleMinimumScaleFactor: CGFloat = 1.0, kTextFont: UIFont = UIFont.systemFont(ofSize: 14),
      kButtonFont: UIFont = UIFont.boldSystemFont(ofSize: 14), showCircularIcon: Bool = true,
      shouldAutoDismiss: Bool = true, contentViewCornerRadius: CGFloat = 5.0,
      fieldCornerRadius: CGFloat = 3.0, buttonCornerRadius: CGFloat = 3.0,
      hideWhenBackgroundViewIsTapped: Bool = false, circleBackgroundColor: UIColor = UIColor.white,
      contentViewColor: UIColor = .hex(0xFFFFFF), contentViewBorderColor: UIColor = .hex(0xCCCCCC),
      titleColor: UIColor = .hex(0x4D4D4D), dynamicAnimatorActive: Bool = false,
      disableTapGesture: Bool = false, buttonsLayout: SwiftyAlertButtonLayout = .vertical
    ) {
      self.kDefaultShadowOpacity = kDefaultShadowOpacity
      self.kCircleTopPosition = kCircleTopPosition
      self.kCircleBackgroundTopPosition = kCircleBackgroundTopPosition
      self.kCircleHeight = kCircleHeight
      self.kCircleIconHeight = kCircleIconHeight
      self.kTitleTop = kTitleTop
      self.kTitleHeight = kTitleHeight
      self.kWindowWidth = kWindowWidth
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
  }
}
