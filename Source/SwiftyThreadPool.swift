//
//  SwiftyTask.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/10/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import Foundation

public class SwiftyThreadPool
{
    private final var MAX_THREAD_COUNT : Int {
        get {
            var activecpu : UInt32 = 0
            var size = MemoryLayout<UInt32>.size
            sysctlbyname("hw.activecpu", &activecpu, &size, nil, 0)
            let avaliableCount : Int = 2 * Int(activecpu) - 1
            let result : Int = avaliableCount > 3 ? avaliableCount : 3
            return result
        }
    }
    
    open static let defalut: SwiftyThreadPool = {
        return SwiftyThreadPool()
    }()
    
    private final var queue : OperationQueue?
    private init()
    {
        let queue : OperationQueue = OperationQueue()
        queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
        add(prepareEnvironment(), withIdentifier: "me.haoking.environmentOperation")
        self.queue = queue
        NotificationCenter.default.addObserver(self, name: Notification.Name.UIApplicationDidReceiveMemoryWarning, object: nil, selector: ClosureWrapper({ [weak self] (_) in
            
            guard let strongSelf = self else { return }
            strongSelf.removeAll()
        }))
    }
    
    
    private final func prepareEnvironment() -> BlockOperation
    {
        let environmentOperation : BlockOperation = BlockOperation.init {
            
            var context : CFRunLoopSourceContext = CFRunLoopSourceContext.init(version: 0, info: unsafeBitCast(self, to: UnsafeMutableRawPointer.self), retain: nil, release: nil, copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil, perform: nil)
            let runLoopSource : CFRunLoopSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            let runLoop : CFRunLoop = RunLoop.current.getCFRunLoop()
            CFRunLoopAddSource(runLoop, runLoopSource, .defaultMode)
            while Thread.current.isCancelled == false
            {
                _ = autoreleasepool {
                    RunLoop.current.run(mode: .defaultRunLoopMode, before: Date.distantFuture)
                }
            }
        }
        return environmentOperation
    }
    
    public final func add(_ op: Operation, withIdentifier identifier: String? = nil)
    {
        guard let queue = queue else { return }
        op.name = identifier
        queue.addOperation(op)
        queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
    }
    
    @discardableResult
    public final func remove(withIdentifier identifier: String) -> Bool
    {
        var removed = false
        guard let queue = queue else { return removed }
        for (_, op) in queue.operations.enumerated().reversed()
        {
            if op.name == identifier
            {
                op.cancel()
                removed = true
                queue.maxConcurrentOperationCount = MAX_THREAD_COUNT
                break
            }
        }
        return removed
    }
    
    @discardableResult
    public final func removeAll() -> Bool
    {
        var removed = false
        guard let queue = queue else { return removed }
        if queue.operations.isEmpty == false
        {
            for (_, op) in queue.operations.enumerated().reversed()
            {
                op.cancel()
            }
            queue.cancelAllOperations()
            removed = true
        }
        return removed
    }
    
    public final func operation(withIdentifier identifier: String) -> Operation?
    {
        var tagOp: Operation?
        guard let queue = queue else { return tagOp }
        for (_, op) in queue.operations.enumerated().reversed()
        {
            if op.name == identifier
            {
                tagOp = op
                break
            }
        }
        return tagOp
    }
    
    public final var count : Int {
        get {
            guard let queue = queue else { return 0 }
            return queue.operationCount
        }
    }
    
    public final func stop()
    {
        guard let queue = queue else { return }
        queue.isSuspended = false
    }
    
    public final func restart()
    {
        guard let queue = queue else { return }
        queue.isSuspended = true
    }
    
    public final func cancel()
    {
        removeAll()
        queue = nil
    }
    
    deinit
    {
        NotificationCenter.default.removeObserver(self)
        cancel()
    }
}
