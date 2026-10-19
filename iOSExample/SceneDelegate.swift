import UIKit

/// 示例 App 的场景代理。
///
/// iOS 27 起,用 iOS 27 SDK 构建、却没有采用 UIScene 生命周期的 App 一启动就 trap
/// (崩溃栈停在 `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`);
/// 示例 App 原先还是 2017 年模板的 AppDelegate + `window` 写法,UI 测试因此全部起不来。
///
/// 场景配置写在 Info.plist 的 `UIApplicationSceneManifest` 里,并指定了 Main.storyboard:
/// UIKit 会自己建窗口、装上初始视图控制器、赋给下面的 `window`,这里不需要别的代码。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
}
