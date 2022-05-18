# SwiftyUI [![Awesome](https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg)](https://github.com/sindresorhus/awesome)

![Build Status](https://travis-ci.org/haoking/SwiftyUI.svg?branch=master) ![CocoaPods Compatible](https://img.shields.io/cocoapods/v/SwiftyUI.svg) ![Platform](https://img.shields.io/cocoapods/p/SwiftyUI.svg?style=flat) ![Swift 4.0+](https://img.shields.io/badge/Swift-4.0%2B-orange.svg)

High performance and lightweight UIView,  UIImage, UIImageView, UIlabel, UIButton and more.

## Features

- [x] SwiftyView GPU rendering Image and Color
- [x] SwiftyColor — color from Hex, colorRGBA value from UIColor, colors from Image
- [x] UIImage Extensions for Inflation / Scaling / Rounding 
- [x] Auto-Purging In-Memory Image Cache
- [x] SwiftyImageView extension 10+ animations
- [x] SwiftyImageView 150% High performance more than UIImageView, depending on UIView-package, Image-GPU and Image-Cache
- [x] SwiftyLabel 300% High performance more than UIlabel, depending on UIView-package and TextKit
- [x] SwiftyButton 300% High performance more than UIButton, depending on UIControl-package, TextKit and BackgroundImage-Advanced
- [x] SwiftyToast is depend on globalCenter and show the toast without overlap.
- [x] SwiftyAlert contains SuccessAlert, ErrorAlert, WarningAlert, InfoAlert, EditAlert and their special styles.
- [x] lightweight, almost one class for each UI
- [x] UI loading thread-safe
- [x] Block-Package to more easy to use
- [x] Easy and simple to use, all APIs are same to system APIs
- [x] SwiftyThreadPool auto manage threads depends on active CPUs, and autorelease Runloop inside
- [x] SwiftyPromise is a lightweight version of PromiseKit, based partially on Javascript's A+ spec, depends on ThreadPool, an interesting feature is that it can `then` on both main thread and background in one Promise.

## Requirements

- iOS 9.0+
- Xcode 9.0+ (Swift Package Manager requires Xcode 11.0+)
- Swift 4.2+

## Communication

- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## Installation

### Swift Package Manager

[Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies.

> Xcode 11.0+ is required.

To integrate SwiftyUI into your Xcode project using Swift Package Manager, add it to the dependencies value of your `Package.swift`:

```ruby
dependencies: [
    .package(url: "https://github.com/haoking/SwiftyUI.git", .upToNextMajor(from: "1.0.0"))
]
```

### CocoaPods

CocoaPods is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

> CocoaPods 1.1+ is required.

To integrate SwiftyUI into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '8.0'
use_frameworks!

target '<Your Target Name>' do
    pod 'SwiftyUI'
end
```

Then, run the following command:

```bash
$ pod install
```

------

## Usage

### SwiftyView

SwiftyView have a auto GPU rendering on color and Image showing.

```swift
import SwiftyUI

let myView : SwiftyView = SwiftyView().addTo(view)
myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
```

You can also invoke UIView function directly, it also have most of the SwiftyView performance feature.

But if you want to have complete benefits, I suggest you to use SwiftyView, and it actually inherits from UIView.

```swift
let myView : UIView = UIView()
view.addSubview(myView)
myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
```

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

```swift
let myImage : UIImage? = UIImage.load("aImage")
myImage.inflate()
```

> Inflating compressed image formats (such as PNG or JPEG) in a background queue can significantly improve drawing performance on the main thread.

#### Scaling

```swift
let myImage : UIImage? = UIImage.load("aImage")
let size = CGSize(width: 100.0, height: 100.0)

let scaledImage = myImage.reSize(to: size)

let scaledToFitImage = myImage.reSize(toFit: size)

let scaledToFillImage = myImage.reSize(toFill: size)
```

#### Rounded Corners

```swift
let myImage : UIImage? = UIImage.load("aImage")
let radius: CGFloat = 10.0

let roundedImage = myImage.rounded(withCornerRadius: radius)
let circularImage = myImage.roundedIntoCircle()
```

### Image Cache

The `ImageCachePool` in SwiftyUI fills the role of that additional caching layer. It is an in-memory image cache used to store images up to a given memory capacity. When the memory capacity is reached, the image cache is sorted by last access date, then the oldest image is continuously purged until the preferred memory usage after purge is met. Each time an image is accessed through the cache, the internal access date of the image is updated.

```swift
let imageCachePool : ImageCachePool = .defalut
```

#### Add / Remove / Fetch Images

Interacting with the `ImageCache` protocol APIs is very straightforward.

```swift
let imageCachePool : ImageCachePool = .defalut
let myImage : UIImage? = UIImage.load("aImage")

imageCachePool.add(myImage, withIdentifier: "myImage")

let cachedMyImage = imageCachePool.image(withIdentifier: "myImage")

imageCachePool.removeImage(withIdentifier: "myImage")
```

### SwiftyImageView

SwiftyImagView inherits from UIView and ImageSettable Protocol and its extension. Also has a better performance.Yet to provide the foundation of the `SwiftyImagView` extension. Due to the powerful support of these classes, protocols and extensions, the `SwiftyImagView` APIs are concise, easy to use and contain a large amount of functionality.

```swift
let myImage : UIImage? = UIImage.load("btnBG")
let myImageView : SwiftyImageView = SwiftyImageView(myImage).addTo(view)
myImageView.frame = CGRect.init(x: 50, y: 150 + 20, width: 100, height: 100)
```

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

SwiftyToas  is depend on global runloop cente, also show the toast without overlap.

```swift
SwiftyToast.load("This is a Toast")
```

### SwiftyAlert

SwiftyAlert contains SuccessAlert, ErrorAlert, WarningAlert, InfoAlert, EditAlert and their special styles.

```swift
let alert: SwiftyAlertView = .create()

_ = alert.addTextField()

_ = alert.addButton("First Button", action: {
    print("First Button tapped")
})
_ = alert.addButton("Second Button") {
    print("Second button tapped")
}

let theAlert: SwiftyAlertViewResponder = alert.showSuccess("Congratulations", subTitle: "You've just displayed this awesome Pop Up View") //showError, showWarning, showInfo, showEdit
theAlert.setDismissBlock {
    print("Alert Dismissed")
}
```

### SwiftyThreadPool

ThreadPool is used to manage threads which depends on active CPUs, also autorelease Runloop inside.

```swift
let myOperation : BlockOperation = .init {

    print("task2----Thread:\(Thread.current)")
    for i in 1...3
    {
        print("Task-------\(i)")
    }
}

ThreadPool.defalut.add(myOperation)
```

### SwiftyPromise

Everyone knows PromiseKit and its story. I also use this library in my code. But it is too heavy for my code, so I build a lightweight version of PromiseKit, based partially on Javascript's A+ spec, depends on ThreadPool.

If you dont need send value from different threads in a Premise, it will be simple:

```swift
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
        str?.append("aaaaaaaa") // aaaaaaaaabc
        update(str)

    }.then(with: nil, on: .main) { (_, str) in

        print("mainmainmainmainmainmainmain----\(String(describing: str))") // aaaaaaaaabc
    }.catch()
```

------

## To Do List

- **CameraKit**, it is a lightweight camera framework.
- **OpenGL** Video / Image processing.
- **Metal** Video / Image processing.
- **OpenCV** Computer vision processing.
- **Vision Framework** Face Detection.

## License

SwiftyUI is released under the MIT license. See LICENSE for details.
