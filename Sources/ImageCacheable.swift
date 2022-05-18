//
//  ImageCacheable.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 10/3/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public protocol ImageCacheable: AnyObject
{
    var memoryCapacity: UInt64 { get set }
    var preferredMemoryUsage: UInt64 { get set }
    var memoryUsage: UInt64 { get }
    
    func add(_ image: UIImage, withIdentifier identifier: String)
    func removeImage(withIdentifier identifier: String) -> Bool
    func removeAllImages() -> Bool
    func image(withIdentifier identifier: String) -> UIImage?
}

extension ImageCacheable
{
    public var memoryCapacity : UInt64 {
        get {
            guard let obj = objc_getAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.memoryCapacityKey) as? UInt64 else {
                
                memoryCapacity = 100_000_000
                return memoryCapacity
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.memoryCapacityKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    public var preferredMemoryUsage : UInt64 {
        get {
            guard let obj = objc_getAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.preferredMemoryUsageKey) as? UInt64 else {
                
                preferredMemoryUsage = 60_000_000
                return preferredMemoryUsage
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.preferredMemoryUsageKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate var currentMemoryUsage : UInt64 {
        get {
            guard let obj = objc_getAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.currentMemoryUsageKey) as? UInt64 else {
                
                self.currentMemoryUsage = 0
                return self.currentMemoryUsage
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.currentMemoryUsageKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate var synchronizationQueue : DispatchQueue {
        get {
            guard let obj = objc_getAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.synchronizationQueueKey) as? DispatchQueue else {
                
                let name = String(format: "me.haoking.ImageCacheable-%08x%08x", arc4random(), arc4random())
                self.synchronizationQueue = DispatchQueue(label: name, attributes: .concurrent)
                return self.synchronizationQueue
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.synchronizationQueueKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate var cachedImages : [String: CachedImage] {
        get {
            guard let obj = objc_getAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.cachedImagesKey) as? [String: CachedImage] else {
                
                self.cachedImages = [:]
                return self.cachedImages
            }
            return obj
        }
        set {
            objc_setAssociatedObject(self, ImageCacheSwiftyAssociatedKeys.cachedImagesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

extension ImageCacheable
{
    public func add(_ image: UIImage, withIdentifier identifier: String)
    {
        synchronizationQueue.async(flags: [.barrier]) { [weak self] in
            
            guard let strongSelf = self else { return }
            let cachedImage = CachedImage(image, identifier: identifier)
            
            if let previousCachedImage = strongSelf.cachedImages[identifier]
            {
                strongSelf.currentMemoryUsage -= previousCachedImage.totalBytes
            }
            strongSelf.cachedImages[identifier] = cachedImage
            strongSelf.currentMemoryUsage += cachedImage.totalBytes
        }
        
        synchronizationQueue.async(flags: [.barrier]) { [weak self] in
            
            guard let strongSelf = self else { return }
            if strongSelf.currentMemoryUsage > strongSelf.memoryCapacity
            {
                let bytesToPurge = strongSelf.currentMemoryUsage - strongSelf.preferredMemoryUsage
                
                var sortedImages = strongSelf.cachedImages.map { $1 }
                sortedImages.sort {
                    let date1 = $0.lastAccessDate
                    let date2 = $1.lastAccessDate
                    return date1.timeIntervalSince(date2) > 0.0
                }
                
                var bytesPurged = UInt64(0)
                for (_, cachedImage) in sortedImages.enumerated().reversed()
                {
                    strongSelf.cachedImages.removeValue(forKey: cachedImage.identifier)
                    bytesPurged += cachedImage.totalBytes
                    if bytesPurged >= bytesToPurge { break }
                }
                
                strongSelf.currentMemoryUsage -= bytesPurged
            }
        }
    }
    
    @discardableResult
    public func removeImage(withIdentifier identifier: String) -> Bool
    {
        var removed = false
        
        synchronizationQueue.sync {
            if let cachedImage = cachedImages.removeValue(forKey: identifier)
            {
                currentMemoryUsage -= cachedImage.totalBytes
                removed = true
            }
        }
        
        return removed
    }
    
    @discardableResult
    public func removeAllImages() -> Bool
    {
        var removed = false
        
        synchronizationQueue.sync {
            if !cachedImages.isEmpty
            {
                cachedImages.removeAll()
                currentMemoryUsage = 0
                removed = true
            }
        }
        
        return removed
    }
    
    public func image(withIdentifier identifier: String) -> UIImage?
    {
        var image: UIImage?
        
        synchronizationQueue.sync {
            if let cachedImage = cachedImages[identifier]
            {
                image = cachedImage.accessImage()
            }
        }
        
        return image
    }
    
    public var memoryUsage: UInt64
    {
        var memoryUsage: UInt64 = 0
        synchronizationQueue.sync { memoryUsage = currentMemoryUsage }
        return memoryUsage
    }
}

private class ImageCacheSwiftyAssociatedKeys
{
    fileprivate static var memoryCapacityKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    fileprivate static var preferredMemoryUsageKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    fileprivate static var currentMemoryUsageKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    fileprivate static var synchronizationQueueKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    fileprivate static var cachedImagesKey : UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
}

private class CachedImage {
    let image: UIImage
    let identifier: String
    let totalBytes: UInt64
    var lastAccessDate: Date
    
    fileprivate init(_ image: UIImage, identifier: String) {
        self.image = image
        self.identifier = identifier
        self.lastAccessDate = Date()
        
        self.totalBytes = {
            let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let bytesPerPixel: CGFloat = 4.0
            let bytesPerRow = size.width * bytesPerPixel
            let totalBytes = UInt64(bytesPerRow) * UInt64(size.height)
            
            return totalBytes
        }()
    }
    
    fileprivate func accessImage() -> UIImage {
        lastAccessDate = Date()
        return image
    }
}
