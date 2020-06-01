//
//  SwiftyImageView.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/4/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public class SwiftyImageView: UIView, ImageSettable
{
    public var image: UIImage? {
        get { return backgroundImage }
        set {
            backgroundImage = newValue
        }
    }
    
    public init(_ image: UIImage? = nil)
    {
        super.init(frame: .zero)
        self.image = image
        isUserInteractionEnabled = false
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    public final class func load(_ image: UIImage? = nil) -> SwiftyImageView
//    {
//        return SwiftyImageView(image)
//    }
}

public extension SwiftyImageView
{
    enum ImageTransition
    {
        case noTransition
        case crossDissolve(TimeInterval)
        case curlDown(TimeInterval)
        case curlUp(TimeInterval)
        case flipFromBottom(TimeInterval)
        case flipFromLeft(TimeInterval)
        case flipFromRight(TimeInterval)
        case flipFromTop(TimeInterval)
        case custom(
            duration: TimeInterval,
            animationOptions: UIView.AnimationOptions,
            animations: (SwiftyImageView, UIImage) -> Void,
            completion: ((Bool) -> Void)?
        )
        
        /// The duration of the image transition in seconds.
        public var duration: TimeInterval {
            switch self {
            case .noTransition:
                return 0.0
            case .crossDissolve(let duration):
                return duration
            case .curlDown(let duration):
                return duration
            case .curlUp(let duration):
                return duration
            case .flipFromBottom(let duration):
                return duration
            case .flipFromLeft(let duration):
                return duration
            case .flipFromRight(let duration):
                return duration
            case .flipFromTop(let duration):
                return duration
            case .custom(let duration, _, _, _):
                return duration
            }
        }
        
        /// The animation options of the image transition.
        public var animationOptions: UIView.AnimationOptions {
            switch self {
            case .noTransition:
                return UIView.AnimationOptions()
            case .crossDissolve:
                return .transitionCrossDissolve
            case .curlDown:
                return .transitionCurlDown
            case .curlUp:
                return .transitionCurlUp
            case .flipFromBottom:
                return .transitionFlipFromBottom
            case .flipFromLeft:
                return .transitionFlipFromLeft
            case .flipFromRight:
                return .transitionFlipFromRight
            case .flipFromTop:
                return .transitionFlipFromTop
            case .custom(_, let animationOptions, _, _):
                return animationOptions
            }
        }
        
        public var animations: ((SwiftyImageView, UIImage) -> Void)
        {
            switch self {
            case .custom(_, _, let animations, _):
                return animations
            default:
                return { $0.image = $1 }
            }
        }
        
        public var completion: ((Bool) -> Void)?
        {
            switch self {
            case .custom(_, _, _, let completion):
                return completion
            default:
                return nil
            }
        }
    }
    
    final func transition(_ imageTransition: ImageTransition, with image: UIImage)
    {
        UIView.transition(with: self, duration: imageTransition.duration, options: imageTransition.animationOptions, animations: { imageTransition.animations(self, image) }, completion: imageTransition.completion)
    }
}
