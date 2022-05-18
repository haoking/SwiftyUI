//
//  SwiftyToast.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/17/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public final class SwiftyToast
{
    private lazy var toastLabel: SwiftyLabel = { [unowned self] in
        var toastLabel = SwiftyLabel(nil, .white, .init(white: 0.0, alpha: 0.7))
        toastLabel.layer.cornerRadius = 5
        toastLabel.clipsToBounds = true
        toastLabel.padding = 5.0
        toastLabel.font = .systemFont(ofSize: 12)
        return toastLabel
        }()
    
    public init(_ text: String)
    {
        layoutView(text: text)
        SwiftyToastCenter.default.add(self).fire()
    }
    
//    @discardableResult
//    public class func load(_ text: String) -> SwiftyToast
//    {
//        return .init(text: text)
//    }
    
    private func layoutView(text: String)
    {
        toastLabel.text = text
        
        let containerSize: CGSize = SwiftyGlobal.keyWindow.bounds.size
        let constraintSize: CGSize = CGSize(width: containerSize.width * (280.0 / 320.0), height: CGFloat.greatestFiniteMagnitude)
        let fitSize: CGSize = toastLabel.sizeThatFits(constraintSize)
        
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        
        if UIApplication.shared.statusBarOrientation.isPortrait
        {
            width = containerSize.width
            height = containerSize.height
            y = 30.0
        }
        else
        {
            width = containerSize.height
            height = containerSize.width
            y = 20.0
        }
        
        let size: CGSize = .init(width: fitSize.width + 10 + 10, height: fitSize.height + 6 + 6)
        x = (width - size.width) * 0.5
        y = height - (size.height + y)
        toastLabel.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }
    
    fileprivate func show()
    {
        Promise<Void>.firstly(on: .main) {
            self.toastLabel.alpha = 0
            SwiftyGlobal.keyWindow.addSubview(self.toastLabel)
            
            UIView.animate(withDuration: 0.5, delay: 0.0, options: .beginFromCurrentState, animations: {
                self.toastLabel.alpha = 1
            }, completion: { completed in
                UIView.animate(withDuration: 2.5, animations: {
                    self.toastLabel.alpha = 1.0001
                }, completion: { completed in
                    UIView.animate(withDuration: 0.5, animations: {
                        self.toastLabel.alpha = 0
                    }, completion: { completed in
                        self.toastLabel.removeFromSuperview()
                        SwiftyToastCenter.default.finish()
                    })
                })
            })
            }.catch()
    }
    
    public class func cancel()
    {
        SwiftyToastCenter.default.cancelAll()
    }
}

private final class SwiftyToastCenter
{
    private var queueArray: [SwiftyToast] = []
    private var isFinished: Bool = true
    
    public static let `default` = {
        return SwiftyToastCenter()
    }()
    
    private init(){}
    
    @discardableResult
    public func add(_ toast: SwiftyToast) -> SwiftyToastCenter
    {
        queueArray.append(toast)
        return self
    }
    
    public func finish()
    {
        isFinished = true
        fire()
    }
    
    public func fire()
    {
        guard let toast = queueArray.first, isFinished else { return }
        queueArray.removeFirst()
        isFinished = false
        toast.show()
    }
    
    public func cancelAll()
    {
        queueArray.removeAll()
    }
}
