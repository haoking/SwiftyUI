//
//  SwiftyTimer.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/24/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import Foundation

public extension Timer
{
    @discardableResult
    final class func after(_ interval: TimeInterval, _ wrapper: ClosureWrapper<Timer>) -> Timer
    {
        var timer: Timer!
        timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, 0, 0, 0) {_ in
            if let block = wrapper.closure
            {
                block(timer)
            }
        }
        return timer
    }
    
    @discardableResult
    final class func every(_ interval: TimeInterval, _ wrapper: ClosureWrapper<Timer>) -> Timer
    {
        var timer: Timer!
        timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0) { _ in
            if let block = wrapper.closure
            {
                block(timer)
            }
        }
        return timer
    }
    
    final func start(runLoop: RunLoop = .current, modes: [RunLoop.Mode] = [RunLoop.Mode.default])
    {
        for (_, mode) in modes.enumerated().reversed()
        {
            runLoop.add(self, forMode: mode)
        }
    }
}
