# SwiftyUI
![CocoaPods Compatible](https://img.shields.io/cocoapods/v/SwiftyUI.svg)![Platform](https://img.shields.io/cocoapods/p/SwiftyUI.svg?style=flat)

High performance(100%) and lightweight(one class each UI) UIView,  UIImage, UIImageView, UIlabel, UIButton and more.

## Features

- [x] SwiftyView GPU rendering Image and Color
- [x] UIImage Extensions for Inflation / Scaling / Rounding 
- [x] Auto-Purging In-Memory Image Cache
- [x] SwiftyImageView extension 10+ animations
- [x] SwiftyImageView 150% High performance more than UIImageView, depending on UIView-package, Image-GPU and Image-Cache
- [x] SwiftyLabel 300% High performance more than UIlabel, depending on UIView-package and TextKit
- [x] SwiftyButton 300% High performance more than UIButton, depending on UIControl-package, TextKit and BackgroundImage-Advanced
- [x] lightweight, almost one class for each UI
- [x] UI loading thread-safe
- [x] Block-Package to more easy to use
- [x] Easy and simple to use, all APIs are same to system APIs

## Requirements

- iOS 8.0+
- Xcode 8.3+
- Swift 3.1+

## Communication

- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## Installation

### CocoaPods

[CocoaPods](http://cocoapods.org) is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

> CocoaPods 1.1+ is required.

To integrate AlamofireImage into your Xcode project using CocoaPods, specify it in your `Podfile`:

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

### Manually

If you prefer not to use either of the aforementioned dependency managers, you can integrate AlamofireImage into your project manually.

#### Embedded Framework

- Open up Terminal, `cd` into your top-level project directory, and run the following command "if" your project is not initialized as a git repository:

```bash
$ git init
```

- Add AlamofireImage as a git [submodule](http://git-scm.com/docs/git-submodule) by running the following command:

```bash
$ git submodule add https://github.com/haoking/SwiftyUI.git
```

- Open the new `SwiftyUI` folder, and drag the `SwiftyUI.xcodeproj` into the Project Navigator of your application's Xcode project.

  > It should appear nested underneath your application's blue project icon. Whether it is above or below all the other Xcode groups does not matter.

- Select the `SwiftyUI.xcodeproj` in the Project Navigator and verify the deployment target matches that of your application target.

- Next, select your application project in the Project Navigator (blue project icon) to navigate to the target configuration window and select the application target under the "Targets" heading in the sidebar.

- In the tab bar at the top of that window, open the "General" panel.

- Click on the `+` button under the "Embedded Binaries" section.

- You will see two different `SwiftyUI.xcodeproj` folders each with two different versions of the `SwiftyUI.framework` nested inside a `Products` folder.

  > It does not matter which `Products` folder you choose from, but it does matter whether you choose the top or bottom `SwiftyUI.framework`.

- And that's it!

  > The `SwiftyUI.framework` is automagically added as a target dependency, linked framework and embedded framework in a copy files build phase which is all you need to build on the simulator and a device.

------

## Usage

### SwiftyView

SwiftyView have a auto GPU rendering on color and Image showing.

```swift
import SwiftyUI

let myView : SwiftyView = SwiftyView.load().addTo(view)
myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
```

You can also invoke UIView function directly, it also have most of the SwiftyView performance feature.

But if you want to have complete benefits, I suggest you to use SwiftyView, and it actually inherits from UIView.

```swift
let myView : UIView = UIView()
view.addSubview(myView)
myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
```

### SwiftyImage

SwiftyImage offers kinds of extension initialize methods on UIImage , include:

- `name`
- `data`
- `image`

```swift
import SwiftyUI

let myImage : UIImage? = UIImage.load("aImage") //Image name from Assets

let myImage : UIImage? = UIImage.load(imageData) //Image data

let myImage : UIImage? = UIImage.load(aImage, identifier: "aImageTdentifier") //Image obj
```

UIImage init from `load(..)` methods will have a auto Image cach, Also the image cache pool will auto manage depends on cpu and iOS system memory.

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
let myImageView : SwiftyImageView = SwiftyImageView.load(myImage).addTo(view)
myImageView.frame = CGRect.init(x: 50, y: 150 + 20, width: 100, height: 100)
```

#### SwiftyImageView Image Transitions

By default, there is no image transition animation when setting the image on the image view. If you wish to add a cross dissolve or flip-from-bottom animation, then specify an `ImageTransition` with the preferred duration.

```swift
let myImage : UIImage? = UIImage.load("btnBG")
let myImageView : SwiftyImageView = SwiftyImageView.load(myImage).addTo(view)
myImageView.frame = CGRect.init(x: 50, y: 150 + 20, width: 100, height: 100)

let myTransition : SwiftyImageView.ImageTransition = .flipFromBottom(0.2)
        
myImageView.transition(myTransition, with: UIImage.load("aImage")!)
```

### SwiftyLabel

SwiftyLabel is a better performance than UILabel and can be used like a standard UI component. Also, Easier to use than UILabel. Since UIView is inherited instead of UILabel, there is little wasteful processing. It uses the function of TextKit to draw characters.

```swift
let myLable : SwiftyLabel = SwiftyLabel.load("Label", .white, .blue).addTo(view)
myLable.frame = CGRect.init(x: 50, y: 300 + 20 + 20, width: 100, height: 100)
```

### SwiftyButton

SwiftyButton is a better performance than UIButton and can be used like a standard UI component. Also, Easier to use than UIButton because of block-package and mistake double tap IgnoreEvent. Since UIControl is inherited instead of UIbutton, there is little wasteful processing. It uses the function of TextKit to draw characters and Image feature from GPU.

```swift
let myBtn : SwiftyButton = SwiftyButton.load("Button", myImage, ClosureWrapper({ [weak self] (btn) in
            
            guard let strongSelf = self, let btn = btn else { return }
            // do something
                                                                                
})).addTo(view)
myBtn.frame = CGRect(x: 50, y: 450 + 20 + 20 + 20, width: 100, height: 100)
```

------

## License

SwiftyUI is released under the MIT license. See LICENSE for details.