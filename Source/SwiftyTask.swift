//
//  SwiftyTask.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/10/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import Foundation

public enum ThreadPerform: Int {
    case main
    case background
}

public class Promise
{
    private struct Task
    {
        fileprivate var identifier: String?
        fileprivate var perform: ThreadPerform
        fileprivate var op : Operation
        
        private init(_ identifier : String? = nil, _ perform: ThreadPerform = .background, _ op: Operation)
        {
            self.identifier = identifier
            self.perform = perform
            self.op = op
        }
        
        fileprivate static func create(_ identifier : String? = nil, _ perform: ThreadPerform = .background, _ op: Operation) -> Task
        {
            return Task(identifier, perform, op)
        }
        
        fileprivate func start()
        {
            switch perform {
            case .main:
                OperationQueue.main.addOperation(op)
            case .background:
                ThreadPool.defalut.add(op, withIdentifier: identifier)
            }
        }
    }
    
    private var tasks: [Task] = []
    private var alwaysTasks: [Task] = []
    private var errorWrapper : ClosureWrapper<Error>?
    private var isError : Bool = false
    
    private final func operationBuild(_ wrapper: ClosureThrowWrapper) -> Operation
    {
        var wrapper : ClosureThrowWrapper = wrapper
        if wrapper.closure == nil
        {
            wrapper = ClosureThrowWrapper({ })
        }
        let handler = wrapper.closure!

        let op : BlockOperation = BlockOperation.init(block: {
            do {
                try handler()
            }
            catch let error {
                self.isError = true
                self.errorWrapper?.closure!(error)
            }
        })
        op.completionBlock = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.fire()
        }
        return op
    }

    private init(_ identifier : String? = nil, _ perform: ThreadPerform = .background, _ wrapper: ClosureThrowWrapper)
    {
        tasks.append(.create(identifier, perform, operationBuild(wrapper)))
    }
    
    @discardableResult
    public final class func firstly(with identifier : String? = nil, on perform: ThreadPerform = .background, _ wrapper: ClosureThrowWrapper) -> Promise
    {
        return Promise(identifier, perform, wrapper)
    }
    
    public final func then(with identifier : String? = nil, on perform: ThreadPerform = .background, _ wrapper: ClosureThrowWrapper) -> Promise
    {
        tasks.append(.create(identifier, perform, operationBuild(wrapper)))
        return self
    }
    
    public final func always(with identifier : String? = nil, on perform: ThreadPerform = .background, _ wrapper: ClosureThrowWrapper) -> Promise
    {
        let task : Task = .create(identifier, perform, operationBuild(wrapper))
        task.op.completionBlock = nil
        alwaysTasks.append(task)
        return self
    }
    
    public final func `catch`(_ errorWrapper : ClosureWrapper<Error>? = nil)
    {
        self.errorWrapper = errorWrapper
        for (_, task) in alwaysTasks.enumerated().reversed()
        {
            task.start()
        }
        alwaysTasks.removeAll()
        fire()
    }
    
    private final func fire()
    {
        guard isError == false else {
            tasks.removeAll()
            return
        }

        guard let task = tasks.first else { return }
        task.start()
        tasks.removeFirst()
    }
}

public class ThreadPool
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
    
    open static let defalut: ThreadPool = {
        return ThreadPool()
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
