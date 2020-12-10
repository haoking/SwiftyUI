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
    var identifier: String?
    var perform: ThreadPerform
    var op : Operation
    
    private init(_ identifier : String? = nil, _ perform: ThreadPerform = .background, _ op: Operation)
    {
        self.identifier = identifier
        self.perform = perform
        self.op = op
    }
    
    static func create(_ identifier : String? = nil, _ perform: ThreadPerform = .background, _ op: Operation) -> Task
    {
        return Task(identifier, perform, op)
    }
    
    func start()
    {
        switch perform {
        case .main:
            OperationQueue.main.addOperation(op)
        case .background:
            SwiftyThreadPool.defalut.add(op, withIdentifier: identifier)
        }
    }
}

private extension Operation
{
    func complete(with block: (() -> Void)?) -> Operation
    {
        completionBlock = block
        return self
    }
}

public final class Promise<T>
{
    private var tasks: [Task] = []
    private var alwaysTasks: [Task] = []
    private var errorBlock : ((Error) -> Void)?
    private var isError : Bool = false
    
    private var value: T?
    
    private final func operationBuild(_ work: (() throws -> Void)?) -> Operation
    {
        return BlockOperation {
            var work = work
            if work == nil { work = {} }
            do {
                try work!()
            }
            catch let error {
                self.isError = true
                self.errorBlock?(error)
            }
            }.complete(with: { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.fire()
            })
    }
    
    private final func operationBuildT(_ work: @escaping (_ update: (T?) -> (), _ value: T?) throws -> ()) -> Operation
    {
        return BlockOperation {
            do {
                try work(self.update, self.value)
            }
            catch let error {
                self.isError = true
                self.errorBlock?(error)
            }
            }.complete(with: { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.fire()
            })
    }
    
    private init(_ identifier : String? = nil, _ perform: ThreadPerform = .background, _ work: (() throws -> Void)?)
    {
        tasks.append(.create(identifier, perform, operationBuild(work)))
    }
    
    private init(_ identifier : String? = nil, _ perform: ThreadPerform = .background, work: @escaping (_ update: (T?) -> Void, _ value: T?) throws -> Void)
    {
        tasks.append(.create(identifier, perform, operationBuildT(work)))
    }
    
    @discardableResult
    public final class func firstly(with identifier : String? = nil, on perform: ThreadPerform = .background, _ work: (() throws -> Void)?) -> Promise
    {
        return Promise(identifier, perform, work)
    }
    
    @discardableResult
    public final class func firstly(with identifier : String? = nil, on perform: ThreadPerform = .background, work: @escaping (_ update: (T?) -> Void, _ value: T?) throws -> Void) -> Promise
    {
        return Promise(identifier, perform, work: work)
    }
    
    @discardableResult
    public final func then(with identifier : String? = nil, on perform: ThreadPerform = .background, _ work: (() throws -> Void)?) -> Promise
    {
        tasks.append(.create(identifier, perform, operationBuild(work)))
        return self
    }
    
    public final func then(with identifier : String? = nil, on perform: ThreadPerform = .background, work: @escaping (_ update: (T?) -> (), _ value: T?) throws -> Void) -> Promise
    {
        tasks.append(.create(identifier, perform, operationBuildT(work)))
        return self
    }
    
    public final func always(with identifier : String? = nil, on perform: ThreadPerform = .background, _ work: (() throws -> Void)?) -> Promise
    {
        let task : Task = .create(identifier, perform, operationBuild(work))
        task.op.completionBlock = nil
        alwaysTasks.append(task)
        return self
    }
    
    public final func `catch`(_ errorBlock : ((Error) -> Void)? = nil)
    {
        self.errorBlock = errorBlock
        for (_, task) in alwaysTasks.enumerated().reversed()
        {
            task.start()
        }
        alwaysTasks.removeAll()
        fire()
    }
    
    private final func update(_ value: T?)
    {
        self.value = value
    }
    
    private final func fire()
    {
        guard !isError else {
            tasks.removeAll()
            return
        }
        guard let task = tasks.first else { return }
        task.start()
        tasks.removeFirst()
    }
}

