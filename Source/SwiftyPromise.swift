//
//  SwiftyPromise.swift
//  SwiftyUI
//
//  Created by Haochen Wang on 10/14/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import Foundation

public enum ThreadPerform: Int {
    case main
    case background
}

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
            SwiftyThreadPool.defalut.add(op, withIdentifier: identifier)
        }
    }
}

public class Promise
{
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
