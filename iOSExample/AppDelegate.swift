//
//  AppDelegate.swift
//  iOSExample
//
//  Created by Haochen Wang on 10/6/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

/// 窗口与前后台切换都归 SceneDelegate 管(见那里的说明)。原先的 `window` 属性和
/// applicationWillResignActive 等五个空方法属于 App 级生命周期,iOS 26 起已废弃,一并删去。
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

  internal func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Override point for customization after application launch.
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    // 名字与 Info.plist 里 UIApplicationSceneManifest 的那一项一致。
    return UISceneConfiguration(
      name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }
}
