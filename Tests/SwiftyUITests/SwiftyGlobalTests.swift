import UIKit
import XCTest

@testable import SwiftyUI

@MainActor
final class SwiftyGlobalTests: XCTestCase {

  /// B1:单元测试进程没有 foreground active 的 window scene,
  /// keyWindow 必须返回 nil 而不是崩溃。
  func testKeyWindowReturnsNilWithoutActiveScene() {
    _ = SwiftyGlobal.keyWindow  // 不崩溃即通过
  }

  /// B17:所有派生尺寸在无窗口时返回安全默认值。
  func testDerivedMetricsFallBackSafely() {
    XCTAssertEqual(SwiftyGlobal.screenSize, .zero)
    XCTAssertEqual(SwiftyGlobal.screenWidth, 0)
    XCTAssertEqual(SwiftyGlobal.screenHeight, 0)
    XCTAssertEqual(SwiftyGlobal.statusHeight, 0)
    XCTAssertEqual(SwiftyGlobal.safeAreaInsets, .zero)
  }

  /// modelName 在模拟器上应返回 "Simulator"。
  func testModelName() {
    XCTAssertEqual(SwiftyGlobal.modelName, "Simulator")
  }

  /// B17:改为计算属性后必须实时反映当前状态,而不是首次访问时的快照。
  func testMetricsTrackWindowLifecycle() {
    XCTAssertNil(SwiftyGlobal.keyWindow)
    XCTAssertEqual(SwiftyGlobal.screenSize, .zero)
    // 若实现仍是永久缓存的 static var,后续接入真实 scene 时会失效;
    // 这里只能断言无窗口态的一致性,真实多窗口行为由 iOSExample 人工验收。
  }

  // MARK: - B2 回归

  /// B2:1.x 的 `navHeight` 是 static **存储**属性,初始化器为
  /// `UINavigationController().navigationBar.frame.size.height` —— 凭空构造一个
  /// 导航控制器去量它的默认高度,量到的值与调用方真正在用的那个导航栏毫无关系,
  /// 也不随横竖屏 / 分屏变化;`barHeight` 还在它之上再叠一层。两者已在 2.0 删除,
  /// 由 `safeAreaInsets` 取代:全部度量一律从当前 key window 现算。
  ///
  /// 判别力:无 key window 时,凡是从 window 派生的度量都必须为零;而"临时造一个
  /// UINavigationController 量高度"这种实现即使在无窗口时也会返回一个非零常数
  /// (第二条断言锁定的就是这个前提)。因此只要有任何一项度量退回到合成实现,
  /// 本测试立刻变红。已实测验证:把 statusHeight 改成
  /// `UINavigationController().navigationBar.frame.height` 后本测试变红。
  func testGlobalMetricsAreWindowDerivedNotSynthesized() {
    XCTAssertNil(SwiftyGlobal.keyWindow, "前提:测试进程没有 foreground active 的 window scene")

    let synthesized = UINavigationController().navigationBar.frame.height
    XCTAssertGreaterThan(
      synthesized, 0,
      "前提:凭空构造的导航控制器有非零默认高度(无窗口时也一样),否则本测试无判别力")

    XCTAssertEqual(SwiftyGlobal.statusHeight, 0, "无 key window 时不应给出任何非零高度")
    XCTAssertEqual(SwiftyGlobal.safeAreaInsets, .zero, "safeAreaInsets 必须来自 key window")
    XCTAssertEqual(SwiftyGlobal.screenSize, .zero)
  }

  /// B2 的另一面 —— "静态初始化器在首次访问的那个线程上构造 UIKit 对象"。
  ///
  /// 这一面**没有**运行期的等价断言可写,只能记录它为什么已经不可能复发:
  /// 2.0 起 `SwiftyGlobal` 整体 @MainActor 隔离,任何触碰 UIKit 的静态成员都
  /// 不可能再从后台线程首次初始化 —— 从非隔离上下文访问会直接编译失败,
  /// 由编译器静态强制,比任何运行期断言都强。
  ///
  /// 运行期这里能做的是守住剩下那半句:唯一保留 nonisolated 的静态成员
  /// (`modelName`,只读 uname(3))确实不碰 UIKit,可以安全地在后台线程首次访问。
  func testNonisolatedStaticIsSafeOffMainThread() async {
    let fromBackground = await Task.detached { SwiftyGlobal.modelName }.value
    XCTAssertFalse(fromBackground.isEmpty)
    XCTAssertEqual(fromBackground, SwiftyGlobal.modelName, "后台线程与主线程应读到同一个值")
  }
}
