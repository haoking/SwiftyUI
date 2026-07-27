# SwiftyUI 2.0.0 设计文档:Bug 修复与现代化升级

日期:2026-07-26
状态:待评审
目标版本:2.0.0(自 1.8.0 起的破坏性升级)

## 1. 背景

SwiftyUI 是一个 iOS 高性能轻量 UI 基础库,最后一次提交在 2022-05-18。核心做法是绕开系统控件,直接继承 `UIView` / `UIControl` 重写等价组件:图片通过 `layer.contents` 交给 GPU,文字通过 TextKit 自绘,并用 `objc_getAssociatedObject` 在协议扩展中模拟存储属性。

### 1.1 实测现状

在 Xcode 26.6 / Swift 6.3.3 / iOS 26.5 SDK 下的实测结果:

| 配置                                        | 结果                                |
| ------------------------------------------- | ----------------------------------- |
| Swift 5 语言模式 + iOS 9 部署目标(当前配置) | `BUILD SUCCEEDED`,源码零告警        |
| Swift 5 语言模式 + iOS 15 部署目标          | `BUILD SUCCEEDED`,7 条废弃 API 告警 |
| Swift 6 语言模式 + iOS 15 部署目标          | 40 个编译错误                       |

当前之所以零告警,是因为部署目标停在 iOS 9.0——Swift 仅在部署目标 ≥ 废弃版本时才发出废弃诊断。这些问题是被配置掩盖的,不是不存在。

### 1.2 其他现状

- 测试覆盖为零:`iOSExampleTests` 与 `iOSExampleUITests` 均为 Xcode 模板空壳
- CI 失效:`.travis.yml` 指向已停服的 travis-ci.org,README 构建徽章是死链
- 仓库中签入了 1.9 MB 的预编译 `SwiftyUI.framework`(仅 armv7/arm64,无模拟器 slice,非 xcframework)
- 版本声明三处不一致:`Package.swift` 声明 `swiftLanguageVersions: [.v4_2]`,`.swift-version` 写 5.0,xcodeproj 设 `SWIFT_VERSION = 5.0`
- `SwiftyUI.podspec` 缺少 `s.swift_version`
- `iOSExample/iOSExample/` 是 2017-10-06 的遗留副本,`project.pbxproj` 中 0 处引用
- `.gitignore` 未忽略 `.DS_Store`,仓库中已签入多个

## 2. 目标与非目标

### 2.1 目标

1. 修复全部 19 个已定位的 bug(P0 崩溃与数据竞争 9 个、P1 语义错误 6 个、P2 设计缺陷 4 个;其中 B19 于计划阶段追加,见 §4.4)
2. 部署目标提升至 iOS 15.0,替换所有废弃 API
3. 迁移到 Swift 6 语言模式,`swiftLanguageModes: [.v6]` 下零错误零告警
4. 建立真实的单元测试,覆盖全部纯逻辑模块及每一条 bug 的回归
5. CI 迁移到 GitHub Actions
6. 清理仓库卫生问题
7. 发布 2.0.0,提供迁移指南

### 2.2 非目标

- 不重写核心渲染策略(`layer.contents` + TextKit 自绘的架构保持不变)
- 不新增功能特性(README "To Do List" 中的 CameraKit / OpenGL / Metal / OpenCV / Vision 均不在本次范围)
- 不删除 `SwiftyPromise` / `SwiftyThreadPool`(保留并修正,另加 async 桥接)
- 不引入任何第三方依赖

## 3. 关键决策

| 决策点                      | 结论                           | 理由                                                                                              |
| --------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------- |
| 最低 iOS 版本               | 15.0                           | Xcode 26 推荐值。scene API / `statusBarManager` / `windowScene` 可无条件使用,零 `#available` 分支 |
| API 兼容性                  | 允许破坏,发 2.0.0              | Swift 6 隔离标注本身即为破坏性;诚实标 major 版本号                                                |
| `SwiftyGlobal` 形态         | `@MainActor` 计算属性,实时查询 | 全局单值缓存在旋转/分屏/多窗口下必然失效;UIKit 内部已有缓存,实时查询开销可忽略                    |
| associated object 存储      | 下沉为真实存储属性             | `TextEditable` 与 `ImageCacheable` 各只有一个实现者;同时解决性能、并发、可读性三个问题            |
| `SwiftyPromise` 定位        | 保留并修正,另加 async 桥接     | README 重点宣传过,是库的卖点之一;不强制调用方迁移                                                 |
| 全局 swizzle                | 改显式开关,默认关              | UI 库改写宿主 App 全局行为风险过高;想要该收益的人显式选择并承担风险                               |
| `SwiftyAlert`               | 按职责拆为 3 个文件            | 需修改的位置分散在 1027 行各处,不拆则后续 diff 难以审查                                           |
| `@MainActor` 破坏后台设属性 | 接受                           | 后台线程修改 UIView 属性本就是未定义行为;README 对应条目改写                                      |

## 4. Bug 清单与修复方案

### 4.1 P0 — 崩溃与数据竞争

**B1. `SwiftyGlobal.swift:21` — `keyWindow` 强解包**

```swift
private(set) static var keyWindow : UIWindow = UIApplication.shared.keyWindow!
```

无 key window 时崩溃。修复:见 5.1,改为返回 `UIWindow?` 的计算属性。

**B2. `SwiftyGlobal.swift:18` — 静态初始化器中创建 UIKit 对象**

```swift
private(set) static var navHeight : CGFloat = UINavigationController().navigationBar.frame.size.height
```

Swift 静态属性初始化器惰性执行(`swift_once`),首次访问若发生在后台线程,即为在非主线程创建 UIKit 对象。Swift 6 编译器独立确认了这一点(`main actor-isolated default value in a nonisolated context`)。修复:删除 `navHeight` / `barHeight`(见 5.1)。

**B3. `ImageSettable.swift:20` — 强制类型转换**

```swift
guard let obj = layer.contents else { return nil }
return UIImage(cgImage: obj as! CGImage)
```

`layer.contents` 可能存放非 `CGImage` 内容(如 `IOSurface`),`as!` 崩溃;且丢失 `scale` 与 `imageOrientation`。修复:改为 `as?` 条件转换并保留原始 `UIImage` 引用(见 5.6)。

**B4. `ImageCacheable.swift:146,162,178` — 并发队列上用 `sync` 执行写操作**

队列声明为 `attributes: .concurrent`。`removeImage` / `removeAllImages` 在普通 `sync` 块中修改 `cachedImages` 和 `currentMemoryUsage`,与 `add` 的 `.barrier` 写、`image(withIdentifier:)` 的 `sync` 读三方竞争。叠加 B5 的存储形态,字典的"取-复制-修改-存回"在并发下必然丢更新。修复:见 5.3。

**B5. `ImageCacheable.swift:108,136,149` — `UInt64` 下溢**

```swift
strongSelf.currentMemoryUsage -= previousCachedImage.totalBytes
currentMemoryUsage -= cachedImage.totalBytes
strongSelf.currentMemoryUsage -= bytesPurged
```

计数一旦因 B4 的竞争漂移,`UInt64` 减法即 trap。修复:统一改用带下限钳制的算术,并由单一锁保证计数与字典同步更新。

**B6. `SwiftyColor.swift:158-160` — 排序谓词违反严格弱序**

```swift
let sortComparator: (CountedColor, CountedColor) -> Bool = { (a, b) -> Bool in
  return a.count <= b.count
}
```

`sort(by:)` 要求谓词是严格弱序,传入 `<=` 属未定义行为。修复:改为 `<`(方向见 4.2 B12 的说明)。

**B7. `SwiftyPromise.swift:59,61` — 跨线程无同步状态**

`isError` 和 `value` 由运行在线程池上的多个 operation 读写,无任何同步。修复:见 5.4。

**B8. `SwiftyToast.swift:97-98` — `SwiftyToastCenter` 状态无同步**

`queueArray` 与 `isFinished` 在 `add`(调用方线程)与 `finish`/`fire`(主线程)之间竞争。修复:整体标 `@MainActor`。

### 4.2 P1 — 语义错误

**B9. `SwiftyThreadPool.swift:33` — 常驻 RunLoop operation 从未入队**

```swift
private init() {
    let queue : OperationQueue = OperationQueue()
    queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
    add(prepareEnvironment(), withIdentifier: "me.haoking.environmentOperation")  // ← queue 此时仍为 nil
    self.queue = queue
    ...
}
```

`add` 内部 `guard let queue = queue else { return }` 直接返回,该 operation 从未入队。README 宣传的 "autorelease Runloop inside" 实际不生效。修复:调整赋值顺序。

**B10. `SwiftyThreadPool.swift:125-135` — `stop` / `restart` 语义颠倒**

```swift
public func stop()    { queue.isSuspended = false }   // ← 应为 true
public func restart() { queue.isSuspended = true }    // ← 应为 false
```

修复:互换。

**B11. `SwiftyPromise.swift:143-148` — `always` 在链条之前执行**

```swift
public final func `catch`(_ errorBlock : ((Error) -> Void)? = nil) {
    self.errorBlock = errorBlock
    for (_, task) in alwaysTasks.enumerated().reversed() { task.start() }  // ← 先启动
    alwaysTasks.removeAll()
    fire()                                                                  // ← 主链条才开始
}
```

`always` 任务被立即投递到线程池,而主链条此时才开始。执行顺序取决于队列调度,绝非"最后总会执行"。修复:见 5.4,改为在链条终结(成功或失败)后执行。

**B12. `SwiftyColor.swift:197` — 整数除法使阈值失效**

```swift
for countedColor in sortedColors where CGFloat(countedColor.count / proposedEdgeColor.count) > 0.3
```

`count` 均为 `Int`,先做整数除法再转 `CGFloat`,结果非 0 即 ≥ 1,`0.3` 这个阈值形同虚设。修复:`CGFloat(countedColor.count) / CGFloat(proposedEdgeColor.count)`。

**排序方向存疑(需测试确认)**:`sortComparator` 为升序,而 `sortedColors.first` 被当作"主导边缘色"使用——按算法意图应取出现次数最多的颜色,当前取到的是最少的。后续 `for (_, countedColor) in sortedColors.enumerated()` 挑选主色时同样从最罕见的颜色开始。**实施时先写测试固定当前输出,确认方向确实颠倒后再改,并在测试中记录修正前后的差异。** 不在本设计中预先断言结论。

**B13. `SwiftyColor.swift:84-95` — `isDistinct` 内层分支是死代码**

```swift
if abs(redValue - color.redValue) > threshold || ... {
    if abs(redValue - greenValue) < 0.03 && abs(redValue - blueValue) < 0.03 {
        if abs(color.redValue - color.greenValue) < 0.03 && ... {
            result = false        // ← 被下一行无条件覆盖
        }
    }
    result = true                 // ← 无条件执行
}
```

修复:内层判定命中时应 `return false`(两色都接近灰度,不算"可区分")。

**B14. `SwiftyImage.swift:17,27,37,59` — 局部 `NSLock` 无互斥效果**

```swift
var image : UIImage?
let lock = NSLock()      // ← 每次调用新建
lock.lock()
image = UIImage(data: data)
lock.unlock()
```

每次调用新建的锁不与任何其他调用竞争,是纯粹的性能损耗。修复:直接删除;真正需要保护的共享状态在 `ImageCachePool` 内部处理。

### 4.3 P2 — 设计缺陷

**B15. `SwiftyView.swift:41-50` — 全 App 范围 swizzle**

`methodExchange` 对 `UIView` 类本身交换 `backgroundColor` 与 `alpha` 的 setter,影响宿主 App 中的每一个 `UIView`;且由首次调用 `addTo(_:)` 惰性触发,导致 App 行为取决于是否曾调用过该方法。修复:见 5.5。

**B16. `SwiftyPromise.swift:140` — 不调 `.catch()` 则永不执行且泄漏**

链条的唯一启动点是 `catch()` 中的 `fire()`。若调用方省略 `.catch()`,整条链不执行;而 Promise 靠 operation 闭包对自身的强引用存活,无人释放。修复:见 5.4,新增显式终结符并在文档中明确"链条必须终结"。

**B17. `SwiftyGlobal.swift:13-21` — 全局单值尺寸 + 永久缓存**

见 5.1。

**B18. `SwiftyThreadPool.swift:145` 与 `SwiftyImage.swift:230` — `removeObserver` 与注册方式不匹配**

两处 `deinit` 都调用 `NotificationCenter.default.removeObserver(self)`,但观察者是用基于 block 的 `addObserver(forName:object:queue:using:)` 注册的——该 API 返回一个 token 作为观察者,`self` 从未被注册,因此这行代码不移除任何东西。

**实际影响为零**:两者都是永不销毁的单例,`deinit` 不会执行。仅作为正确性修复列出,**不为其编写回归测试**(单例的 `deinit` 无法在测试中触发)。修复:持有 `addObserver` 返回的 token 并在 `deinit` 中移除它。

### 4.4 计划阶段追加

**B19. `SwiftyColor.swift:31-43` — `UIColor.hex(String)` 对非法字符崩溃**

本条在编写实施计划、为 hex 解析设计测试用例时发现,不在最初的 §4.1–4.3 清单中。归类为 P0(崩溃)。

```swift
    final class func hex(_ hexString: String, _ alpha: CGFloat = 1.0) -> UIColor
    {
        var hex : String = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard hex.count == 3 || hex.count == 6 else { return UIColor(white: 1.0, alpha: 0.0) }
        if hex.count == 3 { /* 逐字符展开为 6 位 */ }
        return .hex(UInt(hex, radix: 16)!, alpha)   // ← 强解包
    }
```

`guard` 只校验长度,不校验字符。`hex("zzz")` 长度合法,展开成 `"zzzzzz"` 后 `UInt(_:radix: 16)` 返回 `nil`,强解包崩溃。任何把用户输入或配置文件内容直接传入的调用方都会踩到。

修复:把强解包改为 `guard let`,解析失败时与长度非法时保持一致,返回全透明白色。

**bug 总数由 18 增至 19**(P0 由 8 增至 9)。§2.1、§7、§10 中提及的数量与覆盖范围相应包含本条。

## 5. 架构调整

### 5.1 `SwiftyGlobal`

改为 `@MainActor public enum`,所有属性实时计算:

```swift
@MainActor
public enum SwiftyGlobal {
    public static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }
    public static var screenSize: CGSize { keyWindow?.bounds.size ?? .zero }
    public static var screenWidth: CGFloat { screenSize.width }
    public static var screenHeight: CGFloat { screenSize.height }
    public static var statusHeight: CGFloat {
        keyWindow?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
    }
    public static var safeAreaInsets: UIEdgeInsets { keyWindow?.safeAreaInsets ?? .zero }
    public static let modelName: String = { /* uname,设备表补齐至当前 */ }()
}
```

变更明细:

- `keyWindow` 类型由 `UIWindow` 变为 `UIWindow?`,消除强解包(B1)
- **删除 `navHeight` 与 `barHeight`**:`UINavigationController().navigationBar.frame.size.height` 求的是一个临时导航控制器的默认高度,与调用方实际使用的导航栏无关,且随横竖屏变化(B2)。替代方案是 `safeAreaInsets`
- **新增 `safeAreaInsets`**:iOS 15 基线下这是布局的正确依据
- `modelName` 保留,设备映射表补齐至当前已知型号;未知型号仍返回原始 identifier(现有 `default` 分支行为)

`ClosureVoidWrapper` / `ClosureWrapper<T>` 保留在本文件,标注 `Sendable` 约束由使用方决定。文件末尾两大段被注释掉的 `NotificationCenter` / `NSLock` 扩展(第 111-175 行)删除。

### 5.2 `TextEditable` → `SwiftyLabel`

`TextEditable` 当前用 9 个 associated object 模拟存储属性,唯一实现者是 `SwiftyLabel`。`draw(_:)` 每次调用都要经由 `mergedAttributedText` 读取 `font` / `textColor` / `paragraphStyle` / `shadow`,即每帧每个 label 至少 4 次 `objc_getAssociatedObject`(哈希查找 + 内部锁)。

调整:

- 9 个属性(`usesIntrinsicContentSize`、`textAlignment`、`font`、`textColor`、`paragraphStyle`、`shadow`、`attributedText`,以及经由 `container` 的 `numberOfLines`、`padding`、`lineBreakMode`)下沉为 `SwiftyLabel` 的 stored property,配 `didSet { setNeedsDisplay() }`
- `container: NSTextContainer` 与 `layoutManager: NSLayoutManager` 由 associated object 改为 `let` 常量,`loadText()` 中的 `layoutManager.addTextContainer(container)` 移入 `init`
- `TextEditable` 退化为纯接口(`public protocol TextEditable: UIView`),仅声明需求,不提供带存储的默认实现;`overrideDraw` / `overrideSizeThatFits` / `overrideIntrinsicContentSize` / `overrideSizeToFit` 这套间接层随之取消,逻辑直接写在 `SwiftyLabel` 上
- setter 中的 `if Thread.isMainThread { setNeedsDisplay() }` 判断删除——`@MainActor` 已保证在主线程
- `TextEditable.swift:360` 的 `textColor!` 强解包随之消失(改为非可选 stored property,默认 `.black`)

**破坏性影响**:从后台线程设置 `SwiftyLabel` 属性将变成编译错误。README 中 "UI loading thread-safe" 一条需改写为说明本库要求 UI 操作在主线程,由编译器强制。

### 5.3 `ImageCacheable` → `ImageCachePool`

同样是"5 个 associated object 服务唯一实现者"的形态,且是数据竞争的重灾区。

调整:

- `memoryCapacity`、`preferredMemoryUsage`、`currentMemoryUsage`、`cachedImages` 下沉为 `ImageCachePool` 的 stored property
- 移除并发队列 + `barrier`/`sync` 混用的模型,改为单把 `NSLock` 保护全部状态(缓存操作都是短临界区,锁的开销低于原方案的队列派发)
- `currentMemoryUsage` 的增减与 `cachedImages` 的修改在同一临界区内完成,消除计数漂移(B4/B5)
- 内存计数改用带下限钳制的减法
- `ImageCacheable` 退化为纯接口
- `ImageCachePool` 标注为 `final class ... : @unchecked Sendable`(内部由锁保证),使其可作为 `static let` 单例在 Swift 6 下通过

**API 拼写修正**:`ImageCachePool.defalut` → `ImageCachePool.default`。旧名保留为 `@available(*, deprecated, renamed: "default")` 别名,编译器提示迁移。`SwiftyThreadPool.defalut` 同样处理。

### 5.4 `SwiftyPromise` 与 `SwiftyThreadPool`

`SwiftyPromise`:

- 内部状态(`tasks`、`alwaysTasks`、`value`、`isError`、`errorBlock`)由一把私有串行 `DispatchQueue` 保护(B7)
- `always` 语义修正:改为在链条终结(全部任务完成或遇错短路)后执行,而非 `catch()` 时立即启动(B11)
- 新增显式终结符 `public func start()`,使"不带错误处理的链条"也能正常启动,不再必须写 `.catch()`(B16);`catch(_:)` 保留原有终结语义,内部与 `start()` 共用同一实现
- 新增 async 桥接:`public func value() async throws -> T?`,终结链条并以 `await` 取回结果;链条中的错误经由 `throws` 抛出。现有链式 API 签名不变
- `Task` 结构体与 `Operation.complete(with:)` 扩展保持内部私有;`Task` 需重命名(与 Swift 并发的 `Task` 同名,在 Swift 6 下易产生歧义),改为 `PromiseTask`

`SwiftyThreadPool`:

- 修正 `init` 中的赋值顺序,使常驻 RunLoop operation 真正入队(B9)
- 互换 `stop` / `restart` 的实现(B10)
- `queue` 的读写加锁,类标注 `@unchecked Sendable`
- `deinit` 中的 `removeObserver(self)` 修正为持有并移除 token(B18);`ImageCachePool` 同样处理

### 5.5 `SwiftyView` 与全局 swizzle

- `SwiftyView` 通过自身的 `backgroundColor` / `alpha` property observer 维护 `isOpaque`,不依赖 swizzle;`SwiftyLabel` / `SwiftyButton` / `SwiftyImageView` 同理
- `UIView.addTo(_:)` 保留(纯便利方法),但移除其中触发 `methodExchange` 的副作用
- 全局优化抽为显式 API:

```swift
@MainActor
public enum SwiftyUI {
    /// 为宿主 App 中所有 UIView 自动维护 isOpaque。
    /// 这会 swizzle UIView 的 backgroundColor 与 alpha setter,影响整个 App。
    /// 只能调用一次,且必须在主线程。默认不启用。
    public static func enableGlobalOpaqueOptimization()
}
```

- `NSObject.swizzleInstance` / `swizzleStatic` 由 `public` 降为 `internal`——这两个方法当前是公开 API,但属于实现细节

### 5.6 `ImageSettable`

`ImageSettable` 有两个实现者(`SwiftyButton`、`SwiftyImageView`),协议扩展当前通过 `layer.contents` 的读写实现 `backgroundImage`,不使用 associated object。

问题在于 getter 的 `obj as! CGImage`(B3):`layer.contents` 可能存放非 `CGImage` 内容而崩溃,且 `CGImage` → `UIImage` 的往返会丢失 `scale` 与 `imageOrientation`。

调整方式与 5.2 / 5.3 保持一致——用真实存储替代从 layer 反推,**不引入新的 associated object**:

- 协议声明存储需求:`var backgroundImage: UIImage? { get set }`
- 两个实现者各自提供 stored property,`didSet` 中同步 `layer.contents = backgroundImage?.cgImage` 并更新 `isOpaque`
- 共享的 `didSet` 逻辑抽为协议扩展中的 `internal` 辅助方法,避免两处重复
- getter 直接返回存储的 `UIImage`,`scale` / `imageOrientation` 完整保留,`as!` 崩溃路径彻底消失

`SwiftyImageView.image` 作为 `backgroundImage` 的别名保持不变。

### 5.7 `SwiftyButton`

- `tapHandler` 与 `isIgnoreEvent` 由 associated object 改为 stored property
- **`tapForwardHandlerWrapper` 及其 key 整块删除**——已确认只有存取器定义,无任何调用点
- 防重复点击的 1 秒延迟改为可配置属性(默认 1.0),`perform(_:with:afterDelay:)` 中多余的 `with: self` 参数移除
- `sendAction` 的 swizzle 保留(它正确地作用于 `SwiftyButton` 自身而非全局 `UIControl`),但改为在类型初始化时确定性安装

### 5.8 `SwiftyToast`

- `SwiftyToast` 与 `SwiftyToastCenter` 整体标 `@MainActor`,队列状态自然安全(B8)
- `UIApplication.shared.statusBarOrientation` 替换为 `windowScene.interfaceOrientation`
- `SwiftyGlobal.keyWindow` 变为可选后,`layoutView` / `show` 需处理无窗口的情况(静默丢弃该 toast)
- 内部对 `Promise` 的使用改为直接在主线程执行(已在 `@MainActor` 上,无需绕道 Promise)

### 5.9 `SwiftyAlert` 拆分

当前单文件 1027 行,需修改的位置(4 处 `keyWindow`、5 个静态绘制缓存)分散在各处。按职责拆为三个文件:

| 文件                     | 内容                                                                              |
| ------------------------ | --------------------------------------------------------------------------------- |
| `SwiftyAlertView.swift`  | `SwiftyAlertView`、`SwiftyAlertViewResponder`、`SwiftyAlertButton`、显示/隐藏逻辑 |
| `SwiftyAlertStyle.swift` | `SwiftyAlertViewStyle`、`SwiftyAlertButtonLayout`、`SwiftyAppearance`             |
| `SwiftyAlertIcons.swift` | `SwiftyAlertViewStyleKit` 的图标绘制与缓存                                        |

拆分为纯移动,不改变任何逻辑;随后在各自文件内完成 `keyWindow` 替换与 `@MainActor` 标注。图标缓存(`imageOfCheckmark` 等 5 个静态属性)改为 `@MainActor` 下的惰性常量。

## 6. Swift 6 与 iOS 15 迁移

### 6.1 配置变更

| 文件                 | 当前                                                         | 目标                                                   |
| -------------------- | ------------------------------------------------------------ | ------------------------------------------------------ |
| `Package.swift`      | tools 5.6 / `.iOS(.v9)` / `swiftLanguageVersions: [.v4_2]`   | tools 6.0 / `.iOS(.v15)` / `swiftLanguageModes: [.v6]` |
| `SwiftyUI.podspec`   | 1.8.0 / `ios.deployment_target = "9.0"` / 无 `swift_version` | 2.0.0 / `"15.0"` / `s.swift_version = "6.0"`           |
| `.swift-version`     | 5.0                                                          | 6.0                                                    |
| `SwiftyUI.xcodeproj` | `IPHONEOS_DEPLOYMENT_TARGET = 9.0` / `SWIFT_VERSION = 5.0`   | `15.0` / `6.0`                                         |

`Package.swift` 同时新增 test target。

### 6.2 40 个 Swift 6 错误的处置

| 类别                                                              | 数量 | 处置                                                                                |
| ----------------------------------------------------------------- | ---- | ----------------------------------------------------------------------------------- |
| `TextEditable` 的 9 个 associated object key                      | 9    | 5.2 的存储下沉后自然消失                                                            |
| `ImageCacheable` 的 5 个 key                                      | 5    | 5.3 的存储下沉后自然消失                                                            |
| `SwiftyButton` 的 3 个 key                                        | 3    | 5.7 的存储下沉 + 死代码删除后自然消失                                               |
| `SwiftyGlobal` 的 8 个静态属性(含 4 个 main-actor 隔离错误)       | 12   | 5.1 改为 `@MainActor` 计算属性                                                      |
| `SwiftyAlert` 的 5 个静态图标缓存                                 | 5    | 5.9 改为 `@MainActor` 惰性常量                                                      |
| `SwiftyToast` 的静态单例 + main-actor 默认值                      | 2    | 5.8 标 `@MainActor`                                                                 |
| `ImageCachePool.defalut` / `SwiftyThreadPool.defalut` 非 Sendable | 2    | 5.3 / 5.4 标 `@unchecked Sendable`(内部加锁)                                        |
| `UIImage.isInflatedKey`                                           | 1    | `UIImage` 是外部类型,必须保留 associated object;标 `nonisolated(unsafe) static let` |
| `SwiftyPromise` 的 `@Sendable` 闭包赋值                           | 1    | 5.4 的同步化改造中一并处理                                                          |
| 合计                                                              | 40   |                                                                                     |

架构调整完成后,存储下沉类的 17 个错误(`TextEditable` 9 + `ImageCacheable` 5 + `SwiftyButton` 3)自动消解;剩余 23 个属于真正的并发语义问题,逐一处理。

### 6.3 废弃 API 替换

| 位置                                | 废弃 API                                    | 替换                                           |
| ----------------------------------- | ------------------------------------------- | ---------------------------------------------- |
| `SwiftyGlobal.swift:17`             | `UIApplication.shared.statusBarFrame`       | `windowScene.statusBarManager?.statusBarFrame` |
| `SwiftyGlobal.swift:21`             | `UIApplication.shared.keyWindow`            | `connectedScenes` → `UIWindowScene.keyWindow`  |
| `SwiftyToast.swift:47`              | `UIApplication.shared.statusBarOrientation` | `windowScene.interfaceOrientation`             |
| `SwiftyAlert.swift:270,585,694,770` | `UIApplication.shared.keyWindow`            | 同上,经由 `SwiftyGlobal.keyWindow`             |

## 7. 测试策略

新增 `Tests/SwiftyUITests/`,在 `Package.swift` 中注册 test target。测试须覆盖每一条已修 bug 的回归,B18 除外(单例 `deinit` 不可触发,理由见 4.3)。

测试通过 `xcodebuild test -destination 'platform=iOS Simulator,...'` 运行——本包仅依赖 UIKit,`swift test` 在 macOS 宿主上无法工作。

| 测试文件                | 覆盖内容                                                                                                                                                                                                    |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SwiftyColorTests`      | hex 解析(3 位 / 6 位 / 带 `#` / 非法输入);`redValue` 等 rgba 取值(4 分量与 2 分量色彩空间);`isDistinct` 修复后的行为(B13);排序谓词严格弱序(B6);取色算法输出——先固定当前行为,再据以判定排序方向是否颠倒(B12) |
| `ImageCachePoolTests`   | LRU 淘汰顺序;内存计数准确性;超出 `memoryCapacity` 后的清理行为;多线程并发读写压力测试(当前实现必然失败);下溢边界(B4/B5)                                                                                     |
| `SwiftyPromiseTests`    | 链式执行顺序;错误短路(遇错跳过后续 `then`);`always` 在链条结束后执行(B11);无 `.catch()` 时的显式终结(B16);跨线程 `value` 传递的正确性(B7)                                                                   |
| `SwiftyThreadPoolTests` | `add` / `remove(withIdentifier:)` / `operation(withIdentifier:)` / `removeAll`;`count`;`stop` / `restart` 语义(B10);常驻 RunLoop operation 确实入队(B9)                                                     |
| `SwiftyImageTests`      | `reSize(to:)` / `reSize(toFit:)` / `reSize(toFill:)` 的输出尺寸与 scale;`rounded` / `roundedIntoCircle`;`isOpaque` 判定;`inflate` 幂等                                                                      |
| `SwiftyGlobalTests`     | 计算属性在无 window 时返回安全默认值而非崩溃(B1)                                                                                                                                                            |

UI 组件(`SwiftyView` / `SwiftyLabel` / `SwiftyButton` / `SwiftyImageView` / `SwiftyToast` / `SwiftyAlert`)的渲染行为不做自动化断言,但须保证 `iOSExample` 能正常构建与运行,作为人工验收路径。

## 8. CI 与仓库卫生

### 8.1 CI

删除 `.travis.yml`,新增 `.github/workflows/ci.yml`:

- `swift package describe` — 验证 SPM 清单可解析(**不能用 `swift build`**:本包仅依赖 UIKit,在 macOS 宿主上 `swift build` 会因 `cannot load underlying module for 'UIKit'` 失败,已实测确认)
- `xcodebuild build -destination 'generic/platform=iOS Simulator'` — 构建库
- `xcodebuild test -destination 'platform=iOS Simulator,name=<具体机型>'` — 在模拟器上跑单元测试(同理不能用 `swift test`)
- `xcodebuild build -scheme iOSExample` — 验证示例工程可构建
- `pod lib lint` — 验证 podspec 有效

README 徽章更新为 GitHub Actions 徽章。

### 8.2 仓库卫生

- 删除 `SwiftyUI.framework/`(1.9 MB,仅 armv7/arm64,无模拟器 slice,非 xcframework)。分发依赖 SPM 与 CocoaPods 源码集成,不需要签入二进制
- 删除全部 `.DS_Store`,在 `.gitignore` 中追加 `.DS_Store` 与 `*.xcuserdatad/`
- 删除 `iOSExample/iOSExample/`(2017-10-06 遗留副本,`project.pbxproj` 中 0 处引用)
- 删除 `SwiftyGlobal.swift` 中被注释掉的 `NotificationCenter` / `NSLock` 扩展(第 111-175 行)
- 新增 `CHANGELOG.md`,记录 2.0.0 的全部破坏性变更

## 9. 发布与迁移指南

README 需更新:

- Requirements 改为 iOS 15.0+ / Xcode 26.0+ / Swift 6.0
- 构建徽章改为 GitHub Actions
- "UI loading thread-safe" 一条改写为说明本库要求 UI 操作在主线程,由 `@MainActor` 编译期强制
- 新增迁移章节,列出 1.8.0 → 2.0.0 的破坏性变更:

| 变更                                                                 | 迁移方式                                                     |
| -------------------------------------------------------------------- | ------------------------------------------------------------ |
| `ImageCachePool.defalut` → `.default`                                | 编译器提示自动修正;旧名保留一个大版本                        |
| `SwiftyThreadPool.defalut` → `.default`                              | 同上                                                         |
| `SwiftyGlobal.keyWindow` 变为 `UIWindow?`                            | 调用方处理可选                                               |
| `SwiftyGlobal.navHeight` / `barHeight` 删除                          | 改用 `safeAreaInsets`                                        |
| UI 属性须在主线程设置                                                | 将设置代码移入主线程                                         |
| 全局 isOpaque 优化默认关闭                                           | 需要的话显式调用 `SwiftyUI.enableGlobalOpaqueOptimization()` |
| `TextEditable` / `ImageCacheable` 不再提供带存储的默认实现           | 自定义实现者需自行提供存储(实践中无外部实现者)               |
| `NSObject.swizzleInstance` / `swizzleStatic` 由 public 降为 internal | 无替代;这两个方法本属实现细节                                |

版本号统一为 2.0.0(`podspec` / `CHANGELOG` / git tag)。

## 10. 验收标准

1. `xcodebuild build -destination 'generic/platform=iOS Simulator'` 在 `swiftLanguageModes: [.v6]` + iOS 15 部署目标下零错误零告警(源码告警;工程级配置告警不计)
2. 全部单元测试通过,且每条已修 bug 都有对应的回归测试
3. `iOSExample` 可构建、可运行,现有演示功能(视图 / 图片 / 标签 / 按钮 / 定时器 / 取色 / Promise / Toast / Alert)行为正常
4. `pod lib lint` 通过
5. GitHub Actions 全部 job 绿灯
6. 仓库中不再包含 `SwiftyUI.framework/`、`.DS_Store`、`iOSExample/iOSExample/`
7. README、CHANGELOG 与代码实际行为一致

## 11. 风险

| 风险                                                             | 影响                           | 缓解                                                                                           |
| ---------------------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------- |
| `SwiftyColor` 取色算法排序方向若确实颠倒,修正后输出颜色会变化    | 依赖该功能的调用方视觉结果改变 | 先写测试固定当前行为,修正前后差异记入 CHANGELOG;作为 2.0.0 的破坏性变更明示                    |
| `SwiftyAlert` 拆分为纯移动,但 1027 行的搬运有引入错漏的可能      | 弹窗功能回归                   | 拆分与逻辑修改分为两次独立提交,拆分提交须保证 `git diff` 只有位置变化;由 `iOSExample` 人工验收 |
| `@MainActor` 传染范围可能超出预期                                | 调用方改动量大于预期           | 迁移指南明确列出;`iOSExample` 作为真实调用方先行验证                                           |
| 删除签入的 `SwiftyUI.framework` 可能影响以二进制方式集成的使用者 | 该集成方式失效                 | podspec 中 `vendored_frameworks` 本就是注释状态,即当前并未以二进制分发;CHANGELOG 中说明        |
| `TextEditable` 存储下沉改变了公开协议形态                        | 外部自定义实现者受影响         | 已确认库内唯一实现者是 `SwiftyLabel`;外部实现者需自行提供存储,迁移指南说明                     |

## 12. 实施顺序建议

变更之间存在依赖,建议按此顺序推进,每步独立可验证:

1. 仓库卫生清理(删除二进制 / `.DS_Store` / 遗留副本 / 死代码),不涉及逻辑
2. 配置升级至 iOS 15 + Swift 5 语言模式,替换 7 处废弃 API
3. 建立测试脚手架,为现有行为写下基线测试(尤其 `SwiftyColor` 取色)
4. 修复 P0 / P1 bug,每条 bug 先补测试再改代码
5. 架构调整(存储下沉、`SwiftyGlobal` 重写、`SwiftyAlert` 拆分)
6. 切换至 Swift 6 语言模式,处理剩余隔离问题
7. CI 接入
8. 文档与发布(README / CHANGELOG / 版本号)

第 3 步的基线测试必须早于第 4、5 步,否则无法判断重构是否改变了行为。
