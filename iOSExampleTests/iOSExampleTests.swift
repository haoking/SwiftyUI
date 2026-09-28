//
//  iOSExampleTests.swift
//  iOSExampleTests
//
//  Created by Haochen Wang on 10/6/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit
import XCTest

@testable import SwiftyUI

/// 在示例 App 进程里跑的库测试。
///
/// SwiftyUITests(SPM 的测试 target)没有宿主 App:没有 window scene,
/// `SwiftyGlobal.keyWindow` 恒为 nil,凡是"要有窗口才发生"的路径 —— showTitle 的
/// 成功分支首当其冲 —— 在那里都走不到。本 target 以 iOSExample 为宿主(TEST_HOST),
/// 进程里有真实的 scene 与 key window,专门补这一块。
///
/// Xcode 里对 iOSExample scheme 按 ⌘U 会跑它;命令行:
///
///     xcodebuild test -project SwiftyUI.xcodeproj -scheme iOSExample \
///       -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:iOSExampleTests
@MainActor
final class iOSExampleTests: XCTestCase {

  /// 宿主 App 刚启动时 scene 可能还没进入前台活跃,轮询等它。
  private func waitForKeyWindow(timeout: TimeInterval = 5) -> UIWindow? {
    let deadline = Date().addingTimeInterval(timeout)
    while SwiftyGlobal.keyWindow == nil && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return SwiftyGlobal.keyWindow
  }

  /// 有真实 scene 时,全局度量都来自当前的 key window。
  func testGlobalMetricsComeFromKeyWindow() throws {
    let window = try XCTUnwrap(waitForKeyWindow(), "宿主 App 应当有 foreground active 的 key window")
    XCTAssertEqual(SwiftyGlobal.screenSize, window.bounds.size)
    XCTAssertEqual(SwiftyGlobal.safeAreaInsets, window.safeAreaInsets)
  }

  /// showTitle 的成功分支:上屏、默认配色跟随样式、收起后下屏。
  ///
  /// showTitle 的 colorStyle 曾默认为 0x000000 而不是 nil,直接调用时圆圈与按钮是黑色的;
  /// 这条路径要有 key window 才走得到,SPM 测试里验证不了。
  func testShowTitleUsesStyleColorByDefaultAndDismisses() throws {
    let window = try XCTUnwrap(waitForKeyWindow(), "宿主 App 应当有 foreground active 的 key window")
    let alert = SwiftyAlertView.create()
    alert.addButton("OK") {}

    let responder = alert.showTitle("标题", subTitle: "副标题", style: .success)

    XCTAssertTrue(alert.isShowing())
    XCTAssertTrue(alert.view.superview === window)
    XCTAssertEqual(
      alert.circleView.backgroundColor, UIColor.hex(SwiftyAlertViewStyle.success.defaultColorInt),
      "未指定 colorStyle 时应取 style 的默认色")

    responder.close()
    let deadline = Date().addingTimeInterval(3)
    while alert.view.superview != nil && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    XCTAssertNil(alert.view.superview, "close() 之后 alert 应当从窗口上移除")
    XCTAssertFalse(alert.isShowing())
  }
}
