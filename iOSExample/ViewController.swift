//
//  ViewController.swift
//  iOSExample
//
//  Created by Haochen Wang on 10/6/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import SwiftyUI
import UIKit

struct SimpleError: Error {

}

class ViewController: UIViewController {

  /// 屏幕上的事件回显。
  ///
  /// 示例原本只 `print`,回调到底有没有跑、跑了几次,离开 Xcode 控制台就完全
  /// 不可观察 —— 这正是 iOSExample 长期只能"人工看一眼"验收的原因。
  /// 这里把同样的事件同时写到屏幕上:print 一行不删,额外多一份可观察的状态。
  private let eventLog: SwiftyLabel = {
    let label = SwiftyLabel(nil, .white, .init(white: 0.0, alpha: 0.75))
    label.font = .systemFont(ofSize: 11)
    label.padding = 6.0
    label.textAlignment = .topLeft
    label.layer.cornerRadius = 5
    label.clipsToBounds = true
    // SwiftyLabel 用 TextKit 自绘,不像 UILabel 那样自带无障碍暴露,
    // 需要显式声明才能被 VoiceOver 读到、被 UI 测试查询到。
    label.isAccessibilityElement = true
    label.accessibilityTraits = .staticText
    label.accessibilityIdentifier = "EventLog"
    return label
  }()

  private var events: [String] = []

  /// 打印一条事件,并追加到屏幕上的事件回显。
  private func logEvent(_ text: String) {
    print(text)
    events.append(text)
    eventLog.text = events.suffix(10).joined(separator: "\n")
    // accessibilityLabel 用全量而非截断后的文本:UI 测试要断言的是
    // "这个回调确实执行过",不该受可视区域行数影响。
    eventLog.accessibilityLabel = events.joined(separator: " | ")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // 2.0 起全局 isOpaque 优化默认关闭,需显式开启
    SwiftyUI.enableGlobalOpaqueOptimization()

    let myView: SwiftyView = SwiftyView().addTo(view)
    myView.frame = CGRect(x: 50, y: 50, width: 100, height: 100)
    myView.backgroundColor = .black

    let myImage: UIImage? = UIImage.load("btnBG")
    let myImageView: SwiftyImageView = SwiftyImageView(myImage).addTo(view)
    myImageView.frame = CGRect(x: 50, y: 150 + 20, width: 100, height: 100)

    let myLable: SwiftyLabel = SwiftyLabel("Label", .white, .blue).addTo(view)
    myLable.frame = CGRect(x: 50, y: 300 + 20 + 20, width: 100, height: 100)

    let myBtn: SwiftyButton = SwiftyButton(
      "Button", myImage,
      ClosureWrapper({ [weak self] (btn) in

        guard let strongSelf = self, let btn = btn else { return }
        // 每一次真正送达的点击回调都留一条记录:SwiftyButton 的防抖是否生效,
        // 差别就在这条记录出现一次还是三次。
        strongSelf.logEvent("BtnTaped")
        strongSelf.btnTappedSelector(btn)
      })
    ).addTo(view)
    // 放在第二列而不是竖排最底下:Info.plist 声明支持横屏,而横屏时可视高度只有
    // 短边那么多,原来 y = 510 的位置整个落在屏幕外,按钮在横屏下根本点不到。
    myBtn.frame = CGRect(x: 170, y: 280, width: 100, height: 100)
    myBtn.titleLabel.textColor = .white
    // SwiftyButton 继承 UIControl,不像 UIButton 那样自带无障碍暴露:
    // 不设这几项,它在无障碍树里只是一个匿名的 Other,VoiceOver 读不出、
    // UI 测试也点不到。
    myBtn.isAccessibilityElement = true
    myBtn.accessibilityTraits = .button
    myBtn.accessibilityLabel = "Button"
    myBtn.accessibilityIdentifier = "MainButton"

    eventLog.addTo(view)
    eventLog.frame = CGRect(x: 170, y: 50, width: max(view.bounds.width - 190, 100), height: 220)
    eventLog.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

    Timer.every(
      1.0,
      ClosureWrapper({ (timer) in
        print("Timer_every")
      })
    ).start()

    Timer.after(
      5.0,
      ClosureWrapper({ (timer) in
        print("Timer_after")
      })
    ).start()

    myImage?.colors({ (background, primary, secondary, detail) in
      print("background color: \(background)")
      print("primary color: \(primary)")
      print("secondary color: \(secondary)")
      print("detail color: \(detail)")
    })

    print("Main Thread:\(Thread.main)")

    Promise<String>.firstly(on: .background) { (update, _) in

      print("task1----Thread:\(Thread.current)")
      update("abc")

    }.then { (update, str) in

      print("thenthenthenthenthenthen----\(String(describing: str))")
      var str = str
      str?.append("aaaaaaaa")
      update(str)

    }.then(with: nil, on: .main) { (_, str) in

      print("mainmainmainmainmainmainmain----\(String(describing: str))")
    }.catch()

    Promise<Void>.firstly(with: nil, on: .background) {

      print("Promise<Void>---task1----Thread:\(Thread.current)")

    }.then(on: .main) {

      print("Promise<Void>---task2----Thread:\(Thread.current)")
      throw SimpleError()

    }.then {

      print("Promise<Void>---task3----Thread:\(Thread.current)")
    }.always {

      print("Promise<Void>---taskAlways----Thread:\(Thread.current)")

    }.catch { (error) in

      print("Promise<Void>---error\(String(describing: error))")
    }

    // Task 18 新增:Promise.value() 的 async 桥接形式,与上面的回调式链条并存
    Task {
      do {
        let result = try await Promise<String>.firstly(on: .background) { (update, _) in

          print("value()----task1----Thread:\(Thread.current)")
          update("value()-demo")

        }.then(with: nil, on: .main) { (update, str) in

          print("value()----task2----Thread:\(Thread.current)----\(String(describing: str))")
          update(str)

        }.value()

        print("Promise.value() result: \(String(describing: result))")
      } catch {
        print("Promise.value() error: \(error)")
      }
    }
  }

  func btnTappedSelector(_ sender: SwiftyButton) {
    print("safeAreaInsets: \(SwiftyGlobal.safeAreaInsets)")

    var _ = SwiftyToast("btnTappedSelector")

    let alert: SwiftyAlertView = .create()

    _ = alert.addTextField()

    _ = alert.addButton(
      "First Button",
      action: { [weak self] in
        self?.logEvent("First Button tapped")
      })
    _ = alert.addButton("Second Button") { [weak self] in
      self?.logEvent("Second button tapped")
    }

    let theAlert: SwiftyAlertViewResponder = alert.showSuccess(
      "Congratulations", subTitle: "You've just displayed this awesome Pop Up View")
    theAlert.setDismissBlock { [weak self] in
      self?.logEvent("Alert Dismissed")
    }
  }
}
