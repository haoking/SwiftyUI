# SwiftyUI [![Awesome](https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg)](https://github.com/sindresorhus/awesome)

![Build Status](https://github.com/haoking/SwiftyUI/actions/workflows/ci.yml/badge.svg) ![CocoaPods Compatible](https://img.shields.io/cocoapods/v/SwiftyUI.svg) ![Platform](https://img.shields.io/cocoapods/p/SwiftyUI.svg?style=flat) ![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)

High performance and lightweight UIView, UIImage, UIImageView, UIlabel, UIButton and more.

## Features

- [x] SwiftyView GPU rendering Image and Color
- [x] SwiftyColor — color from Hex, colorRGBA value from UIColor, colors from Image
- [x] UIImage Extensions for Inflation / Scaling / Rounding
- [x] Auto-Purging In-Memory Image Cache
- [x] SwiftyImageView extension — 7 built-in image transitions plus a `custom` case
- [x] SwiftyImageView puts the image straight onto `layer.contents` for the GPU to composite, backed by the in-memory image cache
- [x] SwiftyLabel draws its text with TextKit on a plain `UIView`, without UILabel's machinery
- [x] SwiftyButton is a lightweight `UIControl` with a TextKit-drawn title, a GPU-composited background image and built-in tap debouncing
- [x] SwiftyToast queues toasts on a shared, main-actor-isolated centre and shows them one at a time, so they never overlap
- [x] SwiftyAlert contains SuccessAlert, ErrorAlert, WarningAlert, InfoAlert, EditAlert and their special styles.
- [x] lightweight, almost one class for each UI
- [x] UI mutations are confined to the main thread at compile time, enforced via `@MainActor`
- [x] Thread safety is checked by the compiler: shared state sits behind `Mutex` and `Atomic` from the Synchronization module, and nothing in the library is `@unchecked Sendable`
- [x] Block-Package to more easy to use
- [x] Easy and simple to use, all APIs are same to system APIs
- [x] SwiftyThreadPool auto manage threads depends on active CPUs
- [x] SwiftyPromise is a lightweight version of PromiseKit, based partially on Javascript's A+ spec, depends on `SwiftyThreadPool`, an interesting feature is that it can `then` on both main thread and background in one Promise.
- [x] SwiftyPromise chains notice cancellation — since 2.1 a cancelled task fails its chain with `PromiseError.cancelled` instead of carrying on with the previous step's value
- [x] `try await promise.value()` bridges a chain to `async`/`await`; `UIImage.colors()` comes in both a callback and an `async throws` flavour

## Requirements

- iOS 18.0+
- Xcode 26.0+
- Swift 6.2

## Communication

- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## Installation

### Swift Package Manager

[Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies.

> Xcode 26.0+ is required: `Package.swift` declares `swift-tools-version: 6.2`.

To integrate SwiftyUI into your Xcode project using Swift Package Manager

Search Package Dependencies in PROJECT:

```text
SwiftyUI
```

Or, add it to the dependencies value of your `Package.swift`:

<!-- readme-check: skip Package.swift 清单里的片段,不是能放进函数体的语句 -->
```swift
dependencies: [
    .package(url: "https://github.com/haoking/SwiftyUI.git", .upToNextMajor(from: "3.0.0"))
]
```

### CocoaPods

CocoaPods is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

> CocoaPods 1.4.0+ is required (the podspec declares `swift_version`, which older CocoaPods versions ignore).

> CocoaPods trunk stops accepting new versions on December 2, 2026. Versions published before then keep installing as usual; for anything later, point the Podfile at a git tag instead, e.g. `pod 'SwiftyUI', :git => 'https://github.com/haoking/SwiftyUI.git', :tag => '3.0.0'`.

To integrate SwiftyUI into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '18.0'
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

## Migration from 2.x to 3.0

3.0.0 is a breaking upgrade for two reasons: the minimum deployment target rises from iOS 15.0 to iOS 18.0, and the package needs a Swift 6.2 compiler (Xcode 26.0 or later). It also removes the three deprecated APIs that 2.0 said would go in the next major version. The performance work in this release changes no observable result — [CHANGELOG.md](CHANGELOG.md) describes how each rewrite is checked against the 2.1.0 algorithm it replaces.

| Change | Migration |
| --- | --- |
| Minimum deployment target is now iOS 18.0 (was 15.0) | Raise your app's deployment target. The library now uses `Mutex` and `Atomic` from the Synchronization module, which first shipped in iOS 18 |
| A Swift 6.2 compiler (Xcode 26.0+) is required | `Package.swift` declares `swift-tools-version: 6.2`, so an older Xcode refuses to resolve the package. CocoaPods has no such check, so an older compiler stops at a single `#error` that names the requirement |
| `ImageCachePool.defalut` and `SwiftyThreadPool.defalut` have been removed | Use `.default`. Both had been deprecated, with a rename fix-it, since 2.0 |
| `ClosureVoidWrapper` has been removed | The library never used it. Use `ClosureWrapper` |
| `SwiftyAppearance`'s initializer no longer takes `kWindowHeight`, `kTextHeight` or `dynamicAnimatorActive` | Delete those arguments. None of them has had any effect since 2.0 |
| `SwiftyLabel` copies `attributedText`, `paragraphStyle` and `shadow` when you assign them, as UILabel does | Mutating the object you assigned no longer changes the label; assign it again. 2.x re-read these objects on every draw, so in-place changes used to show up at the next redraw |

---

## Migration from 2.0

2.1.0 breaks no signatures: every declaration from 2.0 still compiles, and no call site has to be rewritten. Runtime behaviour is another matter — the table below is the full list. Most of it is about what a **cancelled** promise chain does, and cancellation is not an exotic case, because `SwiftyThreadPool` cancels every operation in its queue when the app takes a memory warning, and `UIImage.colors(_:)` is built on a promise chain. One row stands apart: the `then` / `always`-after-settling row is the only change here that can stop a build in its tracks, since it traps in debug. Read that one before you hand a debug build to testers.

| Change                                                                                                                          | What it means for you                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A cancelled task fails its chain with `PromiseError.cancelled`                                                                  | Previously the chain skipped the cancelled step, carried on with the value the previous step had left behind, and settled _successfully_. A `catch(_:)` handler that never used to fire on a memory warning can now fire; a chain that used to produce a plausible-looking result from stale data now fails instead                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `try await promise.value()` throws `PromiseError.cancelled` when a **chain task** is cancelled, instead of returning stale data | 2.0 returned normally with the previous step's value, which is indistinguishable from a chain that ran in full. Handle the error, or let it propagate. Cancellation of `value()`'s _own_ internal completion task is a separate case and never throws `.cancelled`: that task is dispatched only once the chain has settled, so on a chain that succeeded `value()` returns its final value, and on one that errored the error had already resumed the `await` before the cancellation could be noticed (2.0 suspended permanently in either case, with no timeout). Note that none of this makes `value()` hang-proof — three known cases still hang, all listed under [SwiftyPromise](#swiftypromise) and in `value()`'s documentation comment |
| `try await promise.value()` no longer swallows an error the chain has already raised                                            | Two paths used to lose it. If the chain errored in the instant `value()` was registering itself, the error reached no handler at all and the `await` returned the value the chain happened to be holding. And calling `value()` on a chain that had _already_ settled with an error returned that stale value too, because the error object was never kept. Both now throw the error that terminated the chain. Code that treated a returned value as proof of success was reading a result that may never have been produced                                                                                                                                                                                                                    |
| A `then` or `always` appended to a chain that has already settled calls `assertionFailure`                                      | Debug builds now trap where 2.0 silently did nothing. Such a task could never have run, so this only surfaces code that was already dead — but check for it before handing a debug build to testers                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `UIImage.colors(_:)`'s callback is not invoked when the analysis fails or is cancelled                                          | Behaviour unchanged since 2.0; it is simply documented now. If you show a spinner while it runs, it will spin forever in that case. The new `colors() async throws` reports failure and cancellation instead of going quiet, which is what you want here — but it is `value()` plus a nil check, so it inherits all three of `value()`'s hang cases and is not a guarantee that the `await` ever returns. Stopping the spinner for certain is still your job                                                                                                                                                                                                                                                                                     |

Full detail is in [CHANGELOG.md](CHANGELOG.md).

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

- use `SwiftyView` or `SwiftyLabel`, which keep `isOpaque` in step with their own `backgroundColor` and `alpha`. `SwiftyButton` and `SwiftyImageView` recompute it only when their image is set. None of them subclass `SwiftyView` (`SwiftyLabel` and `SwiftyImageView` subclass `UIView`, `SwiftyButton` subclasses `UIControl`);
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

> The analysis downsamples the image to 250 pixels wide and counts its colours in a single pass — runs of identical neighbouring pixels are added up at once, so flat artwork costs only a few table lookups per row. It then turns colours into `UIColor` only as it considers them, most frequent first, and stops as soon as it has all four.

> The callback is **not** invoked if the analysis fails or is cancelled — and cancellation is not exotic: the analysis runs on `SwiftyThreadPool`, which cancels everything in its queue when the app takes a memory warning. There is no signal of any kind in that case, so a spinner you started before the call will spin forever. This has been true since 2.0; use the `async` variant below when you want failure and cancellation reported rather than swallowed.

The `async` variant runs the same analysis and returns the same four colours, but throws instead of going quiet:

```swift
func applyDominantColor(of image: UIImage) async {
    do {
        let (background, _, _, _) = try await image.colors()
        view.backgroundColor = background
    } catch {
        // PromiseError.cancelled if the analysis was cancelled. (PromiseError.noValue
        // exists too, but the current implementation never throws it here.)
        view.backgroundColor = .systemBackground
    }
}
```

> Being an ordinary `async` function, it resumes on whatever context you awaited it from — there is no main-thread guarantee to inherit, and none is needed. The callback version's guarantee stands unchanged.

> **It is not a hang-proof version.** `colors() async throws` is `Promise.value()` plus a nil check, so it inherits all three of the cases in which `value()` never returns — they are listed under [SwiftyPromise](#swiftypromise), and the third of them is reachable in ordinary use. What it buys you over the callback version is that a failed or cancelled analysis becomes a thrown error instead of silence; it does not buy you a guarantee that the `await` completes. If a spinner must always stop, put your own deadline around the call.

### UIImage Extensions

There are several `UIImage` extensions designed to make the common image manipulation operations as simple as possible.

#### Inflation

`inflate()` forces a compressed image (PNG, JPEG, …) to be decoded now, and records that it has been. Otherwise the decode happens lazily, on the main thread, the first time the image is drawn — precisely when you can least afford it.

```swift
let myImage : UIImage? = UIImage(named: "aImage")
myImage?.inflate()
```

> Do this off the main thread when you are decoding many or large images. Decoding early is only a win if it happens somewhere the main thread isn't waiting.

> `UIImage.load(_:)` already takes care of this before it caches: loading by name caches a copy that is already decoded (made with `preparingForDisplay()`), and `UIImage.load(_:identifier:)` calls `inflate()` on the image you pass in. Either way the cached image counts as inflated, and `inflate()` returns immediately for an image that already is. Calling it on an image that came from `UIImage.load` therefore does nothing at all — hence `UIImage(named:)` above.

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

Recency is the order of a linked list: every `add` and every successful `image(withIdentifier:)` moves that entry to the newest end, and purging removes entries from the oldest end, so a hit or an add costs O(1), plus O(1) for each entry a purge removes. 2.x sorted every entry by an access counter each time the cache went over capacity; 1.x used a `Date` stamp, which ties on any two accesses that land inside the same clock granularity and left the purge order arbitrary among the tied entries. List order cannot tie.

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

SwiftyImageView inherits from UIView and the `ImageSettable` protocol. Also has a better performance, because the image goes straight onto `layer.contents` for the GPU to composite instead of through a `UIImageView` draw pass. The one exception is an image whose orientation is anything other than `.up`, or one with no bitmap behind it (a Core Image result, for instance): `layer.contents` can carry neither the orientation nor such an image, so it is redrawn once into an upright bitmap first.

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

It keeps one text storage for its whole lifetime and rebuilds it only when the text or one of its text attributes changes, so the repeated measuring that Auto Layout does, and every redraw, reuse glyphs that were already generated. Like UILabel, it copies `attributedText`, `paragraphStyle` and `shadow` when you assign them: to change one, assign it again.

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

> Nothing fires until you call `start()`, and the countdown runs from the moment the timer is created, not from `start()` — a timer that waits longer than its interval before being started fires straight away. Create and start it in one expression, as above.

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

`SwiftyThreadPool` manages an `OperationQueue` whose concurrency limit follows the number of active CPUs (`2 × hw.activecpu − 1`, floored at 3), computed once when the pool is created.

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
struct SimpleError: Error {}   // a business error of your own; the library's is `PromiseError`

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

`value()` is an `async`/`await` bridge: it's another terminator, used in place of `catch()`/`start()` when you want to consume the chain's result with `await` instead of a callback. It is `nonisolated(nonsending)`, so it registers on whatever actor you call it from rather than hopping to the global executor first. It suspends until the chain finishes and returns its final value, or throws if the chain errored. If a value was never produced (for example a `Promise<Void>` chain, or one that never called `update(...)`), it returns `nil` rather than throwing.

Terminating twice is harmless here: calling `value()` on a chain that another terminator has already settled returns that chain's final value immediately rather than suspending — and if the chain settled by _erroring_, it rethrows that error. (Before 2.1 the error was not kept, so this case returned the last value instead and the failure was invisible.) Terminating more than once is safe in general — `start()`, `catch(_:)` and `value()` share a single one-way latch, so a second terminator never re-drives a chain that is already running or done. Appending is the opposite: a `then` or `always` added after a chain has settled can never run, and 2.1 traps on it in debug builds.

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

#### Cancellation

A chain's `.background` tasks run on `SwiftyThreadPool`, and the shared pool cancels every operation in its queue when the app takes a memory warning. (`.main` tasks go to the main queue instead, out of the pool's reach.) As of 2.1 a chain notices: if a task is cancelled before its block starts running, the chain fails with `PromiseError.cancelled` rather than skipping that step and carrying on with the previous step's value — _provided the queue can still drain_. Cancelling an operation does not end it; the queue reaching it is what ends it, and only then does the chain hear about it. That proviso applies to `catch(_:)` exactly as much as to `value()`; the bullet below on `value()` still failing to return spells out when it does not hold.

This section is about `Operation` cancellation, which is the only kind a chain reacts to. It is unrelated to Swift's structured concurrency: `await value()` **does not respond to `Task` cancellation** — cancel the surrounding `Task` and the `await` keeps waiting for the chain to settle. Do not reach for this section expecting a cooperative-cancellation story.

```swift
Promise<String>.firstly(on: .background) { (update, _) in
    update("abc")
}.then { (update, str) in
    update((str ?? "") + "!")
}.catch { error in
    if error as? PromiseError == .cancelled {
        print("the chain was cancelled before it could finish")
    } else {
        print("failed: \(error)")
    }
}
```

`value()` throws the same error when a **chain task** is the thing that got cancelled:

```swift
func load() async {
    do {
        let result = try await Promise<String>.firstly(on: .background) { (update, _) in
            update("abc")
        }.value()
        print(result ?? "nil")
    } catch PromiseError.cancelled {
        print("the chain was cancelled before it could finish")
    } catch {
        print("failed: \(error)")
    }
}
```

`PromiseError` is the library's own error type — the one the chain machinery raises, as opposed to whatever your task bodies throw. It has two cases: `.cancelled`, above, and `.noValue`, which only `UIImage.colors()` produces (`value()` itself returns `nil` for a chain that never called `update(...)`, it does not throw).

Four things are worth knowing about the edges of this:

- **A cancel that arrives while a task is running does not count.** The task body isn't interrupted — it runs to completion — so treating it as cancelled would throw away a valid result. The rule is: cancel fails the chain, _unless_ the work had already finished, in which case the chain keeps its result and carries on.
- **The same rule protects `value()`'s own bookkeeping.** `value()` resumes your `await` from an internal `always` task, dispatched once the chain has settled — whether it settled by succeeding or by erroring. Either way, cancelling that operation never costs you the outcome. If the chain errored, the error resumed your `await` before those `always` tasks were dispatched at all, so you get the error and the cancellation changes nothing. If it did not, the chain succeeded and the result is already computed, so `value()` hands you the value rather than throwing `.cancelled` — discarding a finished result to report the cancellation of nothing but library bookkeeping would be the same mistake the previous bullet exists to prevent.
- **`start()` has nowhere to put the error.** It deliberately registers no handler, so a cancelled chain terminated with `start()` stops advancing — though it still settles, and any `always` tasks you attached still run, exactly as they do when a chain errors. Terminate with `catch(_:)` or `value()` if you need to hear about the failure itself. An `always` task of your own that gets cancelled is silent in the other direction — by the time `always` tasks run the chain has settled and there is no error path left, so you get no callback and no signal.
- **`value()` can still fail to return, and cancellation is not fully solved.** Cancelling an operation doesn't end it; the queue reaching it is what ends it. So if the queue cannot drain, nothing fires. Concretely, `await value()` still hangs if the pool was `stop()`ped and never `restart()`ed, if the pool was `cancel()`ed at any point before the chain's next background task was dispatched (`cancel()` drops the internal queue, and `add` silently discards everything after that — a `cancel()` landing mid-chain strands the next step just as surely as one that preceded the chain), or if the pool was cancelled or emptied _while suspended_ — a suspended queue finishes nothing, cancelled operations included. In that last case `restart()` gets you out again if the pool was only emptied; if it was `cancel()`ed there is no way back at all, because `cancel()` drops the internal queue and `restart()` cannot resurrect it. These are the three _known_ cases, and they are listed in `value()`'s documentation comment.

#### A `Promise` is single-use

Once a chain has been terminated and has finished, its task queues are never drained again — so a `then` or `always` appended after that point can never run. Since 2.1 that mistake calls `assertionFailure`, which traps in debug builds; release builds keep doing nothing, as before. Build a new chain instead of reusing a finished one.

---

## To Do List

- **CameraKit**, it is a lightweight camera framework.
- **OpenGL** Video / Image processing.
- **Metal** Video / Image processing.
- **OpenCV** Computer vision processing.
- **Vision Framework** Face Detection.

## License

SwiftyUI is released under the MIT license. See LICENSE for details.
