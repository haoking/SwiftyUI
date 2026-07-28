# SwiftyUI [![Awesome](https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg)](https://github.com/sindresorhus/awesome)

![Build Status](https://github.com/haoking/SwiftyUI/actions/workflows/ci.yml/badge.svg) ![CocoaPods Compatible](https://img.shields.io/cocoapods/v/SwiftyUI.svg) ![Platform](https://img.shields.io/cocoapods/p/SwiftyUI.svg?style=flat) ![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)

High performance and lightweight UIView, UIImage, UIImageView, UIlabel, UIButton and more.

## Features

- [x] SwiftyView GPU rendering Image and Color
- [x] SwiftyColor — color from Hex, colorRGBA value from UIColor, colors from Image
- [x] UIImage Extensions for Inflation / Scaling / Rounding
- [x] Auto-Purging In-Memory Image Cache
- [x] SwiftyImageView extension — 7 built-in image transitions plus a `custom` case
- [x] SwiftyImageView 150% High performance more than UIImageView, depending on UIView-package, Image-GPU and Image-Cache
- [x] SwiftyLabel 300% High performance more than UIlabel, depending on UIView-package and TextKit
- [x] SwiftyButton 300% High performance more than UIButton, depending on UIControl-package, TextKit and BackgroundImage-Advanced
- [x] SwiftyToast queues toasts on a shared, main-actor-isolated centre and shows them one at a time, so they never overlap
- [x] SwiftyAlert contains SuccessAlert, ErrorAlert, WarningAlert, InfoAlert, EditAlert and their special styles.
- [x] lightweight, almost one class for each UI
- [x] UI mutations are confined to the main thread at compile time, enforced via `@MainActor`
- [x] Block-Package to more easy to use
- [x] Easy and simple to use, all APIs are same to system APIs
- [x] SwiftyThreadPool auto manage threads depends on active CPUs
- [x] SwiftyPromise is a lightweight version of PromiseKit, based partially on Javascript's A+ spec, depends on `SwiftyThreadPool`, an interesting feature is that it can `then` on both main thread and background in one Promise.

## Requirements

- iOS 15.0+
- Xcode 16.0+
- Swift 6.0

## Communication

- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## Installation

### Swift Package Manager

[Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies.

> Xcode 16.0+ is required.

To integrate SwiftyUI into your Xcode project using Swift Package Manager

Search Package Dependencies in PROJECT:

```ruby
SwiftyUI
```

Or, add it to the dependencies value of your `Package.swift`:

```ruby
dependencies: [
    .package(url: "https://github.com/haoking/SwiftyUI.git", .upToNextMajor(from: "2.0.0"))
]
```

### CocoaPods

CocoaPods is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

> CocoaPods 1.4.0+ is required (the podspec declares `swift_version`, which older CocoaPods versions ignore).

To integrate SwiftyUI into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '15.0'
use_frameworks!

target '<Your Target Name>' do
    pod 'SwiftyUI'
end
```

Then, run the following command:

```bash
$ pod install
```

---

## Migration from 1.x

2.0.0 is a breaking upgrade: minimum deployment target is now iOS 15.0, and the library is built in Swift 6 language mode. Full bug-fix and "Added" history is in [CHANGELOG.md](CHANGELOG.md); this table is just the breaking changes.

| Change                                                                                                                                                                           | Migration                                                                                                                                                                                                                                                                                                                                                                              |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ImageCachePool.defalut` → `.default`                                                                                                                                            | The compiler fix-it renames call sites automatically; the old (misspelled) name is kept as a deprecated alias for one major version                                                                                                                                                                                                                                                    |
| `SwiftyThreadPool.defalut` → `.default`                                                                                                                                          | Same as above                                                                                                                                                                                                                                                                                                                                                                          |
| `SwiftyGlobal.keyWindow` is now `UIWindow?`                                                                                                                                      | Callers must handle the optional                                                                                                                                                                                                                                                                                                                                                       |
| `SwiftyGlobal.navHeight` / `barHeight` removed                                                                                                                                   | Use `SwiftyGlobal.safeAreaInsets` instead                                                                                                                                                                                                                                                                                                                                              |
| `SwiftyLabel.textColor` is now non-optional `UIColor`                                                                                                                            | Remove any unwrapping                                                                                                                                                                                                                                                                                                                                                                  |
| `UIImage.colors(_:)` dominant-color sort direction changed                                                                                                                       | The internal sort was ascending, so `.first` picked the _least_-frequent edge color; it's now descending and picks the most-frequent one. Background/primary/secondary/detail output for real images can change                                                                                                                                                                        |
| All UI types (`SwiftyView`, `SwiftyLabel`, `SwiftyButton`, `SwiftyImageView`, `SwiftyToast`, `SwiftyAlertView`, `SwiftyGlobal`, …) are now `@MainActor`-isolated                 | Code that reads or writes their properties must run on the main thread; this is enforced at compile time                                                                                                                                                                                                                                                                               |
| `Promise<T>` now requires `T: Sendable`; the closures passed to `firstly`/`then`/`always`/`catch` must be `@Sendable`; `UIImage.colors(_:)`'s callback is `@MainActor @Sendable` | Mostly visible to Swift 6-mode callers doing strict concurrency checking. Make captured state `Sendable`, or adjust closures accordingly                                                                                                                                                                                                                                               |
| The global `isOpaque` optimization is off by default                                                                                                                             | Call `SwiftyUI.enableGlobalOpaqueOptimization()` explicitly if you relied on it. **It is irreversible** — see the note under [SwiftyView](#swiftyview)                                                                                                                                                                                                                                 |
| `TextEditable` / `ImageCacheable` no longer ship a default, associated-object-backed implementation                                                                              | Custom conformers must supply their own storage                                                                                                                                                                                                                                                                                                                                        |
| `TextEditable` and `ImageSettable` are now constrained to `UIView` (they were `AnyObject`)                                                                                       | Non-`UIView` conformers no longer compile. Both protocols only ever made sense on a view — the 1.x default implementations were already declared `where Self: UIView`                                                                                                                                                                                                                  |
| `TextEditable.loadText()` has been removed                                                                                                                                       | No replacement. It existed only to hand the protocol extension's associated-object TextKit stack a text container; that storage is gone, and `SwiftyLabel` now wires up its own stack in `init`                                                                                                                                                                                        |
| `TextEditable.mergedAttributedText` is no longer public                                                                                                                          | No replacement — it was a rendering detail of the removed protocol extension. Read `attributedText` instead                                                                                                                                                                                                                                                                            |
| `SwiftyGlobal` is now an `enum` instead of a `class`                                                                                                                             | Every member was already `static`; the type was never meant to be instantiated. Remove any `SwiftyGlobal()` call or subclass declaration                                                                                                                                                                                                                                               |
| `ImageSettable` now declares a storage requirement (`var backgroundImage: UIImage? { get set }`)                                                                                 | Conformers must provide a real `backgroundImage` stored property **and push it to the layer themselves** by calling `applyBackgroundImage(_:)` — see the conformance example under [SwiftyImageView](#swiftyimageview)                                                                                                                                                                 |
| `NSObject.swizzleInstance` is now internal; `NSObject.swizzleStatic` has been removed entirely                                                                                   | No replacement — both were implementation details                                                                                                                                                                                                                                                                                                                                      |
| `ImageCachePool.add(_:withIdentifier:)` is now synchronous                                                                                                                       | Remove any code that waited/polled for the write to land                                                                                                                                                                                                                                                                                                                               |
| The swizzle of `UIControl.sendAction` has been removed, and tap debounce now covers **less** than it did                                                                         | 1.x swizzled `sendAction(_:to:for:)`, throttling _every_ action sent from a `SwiftyButton` — any control event, any target. 2.0 only debounces the handler you pass to `init`, and only on `.touchUpInside`; actions you register yourself with `addTarget(_:action:for:)` are no longer throttled. The window is now `SwiftyButton.ignoreEventInterval` (default `1.0`; `0` disables) |
| `SwiftyGlobal.modelName` no longer maps known device identifiers to friendly names                                                                                               | It now always returns the raw `uname` identifier for physical devices (e.g. `"iPhone12,1"` instead of `"iPhone 11"`)                                                                                                                                                                                                                                                                   |
| Third-party code posting `UIResponder.keyboardWillShowNotification` / `keyboardWillHideNotification` from a background thread                                                    | While a `SwiftyAlertView` is on screen it observes both notifications and asserts main-thread delivery (`MainActor.assumeIsolated`), trapping if violated. 1.x registered the same two observers without that assertion, so an off-main post raced on unsynchronized state instead of trapping. Post keyboard notifications from the main thread, as UIKit itself does                 |
| Consumers still building in **Swift 5 language mode** lose a runtime guard that used to exist                                                                                    | `SwiftyLabel`'s property setters used to skip `setNeedsDisplay()` when called off the main thread. They no longer check, so they now call into UIKit off-main instead of silently no-op'ing. Swift 6-mode callers are unaffected: `@MainActor` turns the same mistake into a compile error                                                                                             |

---

## Usage

### SwiftyView

SwiftyView have a auto GPU rendering on color and Image showing.

```swift
import SwiftyUI

let myView : SwiftyView = SwiftyView().addTo(view)
myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
```

A plain `UIView` still works, of course — `SwiftyView` inherits from it, so anything you can do with one you can do with the other:

```swift
let myView : UIView = UIView()
view.addSubview(myView)
myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
```

But a plain `UIView` gets none of the `isOpaque` upkeep. In 1.x it appeared to, because the first `addTo(_:)` call anywhere in the process lazily swizzled `backgroundColor` and `alpha` on **every** `UIView` in the host app. 2.0 removed that (see **B15** in the CHANGELOG); `SwiftyView` uses plain property observers on itself instead. You have three options:

- use `SwiftyView` (or `SwiftyLabel` / `SwiftyButton` / `SwiftyImageView`, which are built on it);
- call `myView.updateOpaque()` yourself after changing `backgroundColor` or `alpha`;
- opt back into the global behaviour with `SwiftyUI.enableGlobalOpaqueOptimization()`.

> **`SwiftyUI.enableGlobalOpaqueOptimization()` is irreversible.** It swizzles `UIView.backgroundColor` and `UIView.alpha` for the whole process, including the parts of your app that don't use SwiftyUI. There is no `disable` counterpart and there deliberately never will be: swizzling a second time does not restore the original implementations if another library has swizzled the same pair in the meantime. Decide once at launch — and never call it from a unit test, where it would silently distort every test that runs after it in the same process.

### SwiftyColor

color from Hex

colorRGBA value from UIColor

```swift
import SwiftyUI

let myColor: UIColor = .hex(0xccff00) // .hex("333399")
let redFloat: CGFloat = myColor.redValue //greenValue, blueValue, alphaValue
```

colors from Image, also return block is on main thread:

```swift
import SwiftyUI

let myImage : UIImage? = UIImage.load("aImage")

myImage?.colors({ (background, primary, secondary, detail) in
    print("background color: \(background)")
    print("primary color: \(primary)")
    print("secondary color: \(secondary)")
    print("detail color: \(detail)")
})
```

### UIImage Extensions

There are several `UIImage` extensions designed to make the common image manipulation operations as simple as possible.

#### Inflation

`inflate()` forces a compressed image (PNG, JPEG, …) to be decoded now, and records that it has been. Otherwise the decode happens lazily, on the main thread, the first time the image is drawn — precisely when you can least afford it.

```swift
let myImage : UIImage? = UIImage(named: "aImage")
myImage?.inflate()
```

> Do this off the main thread when you are decoding many or large images. Decoding early is only a win if it happens somewhere the main thread isn't waiting.

> `UIImage.load(_:)` already calls `inflate()` for you before it caches, and `inflate()` returns immediately if the image is already inflated. Calling it on an image that came from `UIImage.load(_:)` therefore does nothing at all — hence `UIImage(named:)` above.

> `UIImage.load(_:)` returns `UIImage?` — it is `nil` when no asset with that name exists. Every example below unwraps it accordingly.

#### Scaling

```swift
let myImage : UIImage? = UIImage.load("aImage")
let size = CGSize(width: 100.0, height: 100.0)

let scaledImage = myImage?.reSize(to: size)

let scaledToFitImage = myImage?.reSize(toFit: size)

let scaledToFillImage = myImage?.reSize(toFill: size)
```

> All three return the receiver unchanged if `size` has a zero width or height, rather than trapping.

#### Rounded Corners

```swift
let myImage : UIImage? = UIImage.load("aImage")
let radius: CGFloat = 10.0

let roundedImage = myImage?.rounded(withCornerRadius: radius)
let circularImage = myImage?.roundedIntoCircle()
```

> Like the scaling methods, both return the receiver unchanged for a zero-sized image instead of trapping.

### Image Cache

The `ImageCachePool` in SwiftyUI fills the role of that additional caching layer. It is an in-memory image cache used to store images up to a given memory capacity. When the memory capacity is reached, entries are purged least-recently-used first until the preferred memory usage after purge is met.

Recency is tracked with a monotonically increasing access counter (`lastAccessSequence`), bumped on every `add` and every successful `image(withIdentifier:)`. 1.x used a `Date` stamp, which ties on any two accesses that land inside the same clock granularity — likely, given that cache hits are far shorter than a clock tick — leaving the purge order effectively arbitrary among the tied entries. A counter cannot tie.

```swift
let imageCachePool : ImageCachePool = .default
```

#### Add / Remove / Fetch Images

Interacting with the `ImageCacheable` protocol APIs is very straightforward.

```swift
let imageCachePool : ImageCachePool = .default

if let myImage = UIImage.load("aImage") {
    imageCachePool.add(myImage, withIdentifier: "myImage")
}

let cachedMyImage = imageCachePool.image(withIdentifier: "myImage")

imageCachePool.removeImage(withIdentifier: "myImage")
```

> `add(_:withIdentifier:)` takes a non-optional `UIImage`, so unwrap first. It is synchronous as of 2.0 — the entry is readable the moment it returns.

### SwiftyImageView

SwiftyImagView inherits from UIView and the `ImageSettable` protocol. Also has a better performance, because the image goes straight onto `layer.contents` for the GPU to composite instead of through a `UIImageView` draw pass.

```swift
let myImage : UIImage? = UIImage.load("btnBG")
let myImageView : SwiftyImageView = SwiftyImageView(myImage).addTo(view)
myImageView.frame = CGRect.init(x: 50, y: 150 + 20, width: 100, height: 100)
```

#### Conforming to `ImageSettable` yourself

`ImageSettable` is a `UIView`-constrained protocol with one requirement, `var backgroundImage: UIImage? { get set }`. A stored property alone is not enough: **you must also push the value to the layer**, by calling the protocol extension's `applyBackgroundImage(_:)`. Nothing does it for you — in 1.x the protocol extension supplied `backgroundImage` itself and round-tripped through `layer.contents`, which could crash on a force-cast and lost `scale` and `imageOrientation` (see **B3** in the CHANGELOG).

```swift
final class MyImageView: UIView, ImageSettable {
    var backgroundImage: UIImage? {
        didSet { applyBackgroundImage(backgroundImage) }   // <- required
    }
}
```

One caveat: Swift does not run a property observer when the property is assigned inside the declaring type's own initializer. If you set `backgroundImage` from `init`, call `applyBackgroundImage(_:)` explicitly right after — `SwiftyButton` does exactly that.

#### SwiftyImageView Image Transitions

By default, there is no image transition animation when setting the image on the image view. If you wish to add a cross dissolve or flip-from-bottom animation, then specify an `ImageTransition` with the preferred duration.

```swift
let myImage : UIImage? = UIImage.load("btnBG")
let myImageView : SwiftyImageView = SwiftyImageView(myImage).addTo(view)
myImageView.frame = CGRect.init(x: 50, y: 150 + 20, width: 100, height: 100)

let myTransition : SwiftyImageView.ImageTransition = .flipFromBottom(0.2)

myImageView.transition(myTransition, with: UIImage.load("aImage")!)
```

### SwiftyLabel

SwiftyLabel is a better performance than UILabel and can be used like a standard UI component. Also, Easier to use than UILabel. Since UIView is inherited instead of UILabel, there is little wasteful processing. It uses the function of TextKit to draw characters.

```swift
let myLable : SwiftyLabel = SwiftyLabel("Label", .white, .blue).addTo(view)
myLable.frame = CGRect.init(x: 50, y: 300 + 20 + 20, width: 100, height: 100)
```

### SwiftyButton

SwiftyButton is a better performance than UIButton and can be used like a standard UI component. Also, Easier to use than UIButton because of block-package and mistake double tap IgnoreEvent. Since UIControl is inherited instead of UIbutton, there is little wasteful processing. It uses the function of TextKit to draw characters and Image feature from GPU.

```swift
let myImage : UIImage? = UIImage.load("btnBG")
let myBtn : SwiftyButton = SwiftyButton("Button", myImage, ClosureWrapper({ [weak self] (btn) in

            guard let strongSelf = self, let btn = btn else { return }
            // do something

})).addTo(view)
myBtn.frame = CGRect(x: 50, y: 450 + 20 + 20 + 20, width: 100, height: 100)
```

### SwiftyTimer

SwiftyTimer is running on RunLoop.

```swift
Timer.every(1.0, ClosureWrapper({ (timer) in
    print("Timer_every")
})).start()

Timer.after(5.0, ClosureWrapper({ (timer) in
    print("Timer_after")
})).start()
```

### SwiftyToast

Toasts never overlap: each one is queued on a shared centre and shown only after the previous one has finished fading out.

```swift
_ = SwiftyToast("This is a Toast")
```

> Creating the toast is what shows it — the initializer enqueues it, so you rarely need to keep the instance. Discard it explicitly with `_ =` to avoid an unused-result warning. `SwiftyToast.cancel()` drops everything still queued.

> No RunLoop is involved. The queue is `@MainActor`-isolated and display is driven by a `Task` on the main actor; 1.x's "global runloop center" is gone. The toast's geometry is computed when it is actually shown, not when it is created, so a toast that waits in the queue across a device rotation still lands correctly — see **B22** in the CHANGELOG.

### SwiftyAlert

SwiftyAlert contains SuccessAlert, ErrorAlert, WarningAlert, InfoAlert, EditAlert and their special styles.

```swift
let alert: SwiftyAlertView = .create()

_ = alert.addTextField()

alert.addButton("First Button", action: {
    print("First Button tapped")
})
alert.addButton("Second Button") {
    print("Second button tapped")
}

let theAlert: SwiftyAlertViewResponder = alert.showSuccess("Congratulations", subTitle: "You've just displayed this awesome Pop Up View") //showError, showWarning, showInfo, showEdit
theAlert.setDismissBlock {
    print("Alert Dismissed")
}
```

### SwiftyThreadPool

`SwiftyThreadPool` manages an `OperationQueue` whose concurrency limit tracks the number of active CPUs (`2 × hw.activecpu − 1`, floored at 3), recomputed on every `add`.

```swift
let myOperation : BlockOperation = .init {

    print("task2----Thread:\(Thread.current)")
    for i in 1...3
    {
        print("Task-------\(i)")
    }
}

SwiftyThreadPool.default.add(myOperation)
```

> `cancel()` tears the internal queue down for good; any `add` after that is silently dropped. 2.0 no longer runs a perpetual RunLoop operation inside the pool — see **B9** in the CHANGELOG.

### SwiftyPromise

Everyone knows PromiseKit and its story. I also use this library in my code. But it is too heavy for my code, so I build a lightweight version of PromiseKit, based partially on Javascript's A+ spec, depends on `SwiftyThreadPool`.

If you dont need send value from different threads in a Premise, it will be simple:

```swift
struct SimpleError: Error {}   // your own error type — SwiftyUI does not ship one

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
```

Also you need to share or send value in different threads in a Promise, you should code as below:

```swift
Promise<String>.firstly(on: .background) { (update, _) in

    print("task1----Thread:\(Thread.current)")
    update("abc")

    }.then { (update, str) in

        print("thenthenthenthenthenthen----\(String(describing: str))") // abc
        var str = str
        str?.append("aaaaaaaa") // abcaaaaaaaa
        update(str)

    }.then(with: nil, on: .main) { (_, str) in

        print("mainmainmainmainmainmainmain----\(String(describing: str))") // abcaaaaaaaa
    }.catch()
```

A chain does nothing until it is explicitly terminated — `.catch()` above is one terminator. If you don't need an error handler, `start()` is a lighter-weight terminator that does the same job:

```swift
Promise<Void>.firstly(with: nil, on: .background) {

    print("task1----Thread:\(Thread.current)")

}.start()
```

`value()` is an `async`/`await` bridge: it's another terminator, used in place of `catch()`/`start()` when you want to consume the chain's result with `await` instead of a callback. It suspends until the chain finishes and returns its final value, or throws if the chain errored. If a value was never produced (for example a `Promise<Void>` chain, or one that never called `update(...)`), it returns `nil` rather than throwing.

`catch(_:)` and `value()` do not interfere with each other, in either order. `catch(_:)` is replace-semantics — calling it twice keeps only the second handler — but it writes only _your_ handler slot, while `value()` registers its own internal one. So a chain can have both a `catch` handler and an outstanding `await`, and an error reaches both: your handler first, then the `await` rethrows it.

```swift
func run() async throws {
    let result = try await Promise<String>.firstly(on: .background) { (update, _) in
        update("abc")
    }.then { (update, str) in
        update((str ?? "") + "!")
    }.value()

    print(result ?? "nil") // "abc!"
}
```

---

## To Do List

- **CameraKit**, it is a lightweight camera framework.
- **OpenGL** Video / Image processing.
- **Metal** Video / Image processing.
- **OpenCV** Computer vision processing.
- **Vision Framework** Face Detection.

## License

SwiftyUI is released under the MIT license. See LICENSE for details.
