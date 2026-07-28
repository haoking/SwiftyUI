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
        print("BtnTaped")
        strongSelf.btnTappedSelector(btn)
      })
    ).addTo(view)
    myBtn.frame = CGRect(x: 50, y: 450 + 20 + 20 + 20, width: 100, height: 100)
    myBtn.titleLabel.textColor = .white

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
      action: {
        print("First Button tapped")
      })
    _ = alert.addButton("Second Button") {
      print("Second button tapped")
    }

    let theAlert: SwiftyAlertViewResponder = alert.showSuccess(
      "Congratulations", subTitle: "You've just displayed this awesome Pop Up View")
    theAlert.setDismissBlock {
      print("Alert Dismissed")
    }
  }
}
