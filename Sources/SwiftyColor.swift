//
//  SwiftyColor.swift
//  WHCWSIFT
//
//  Created by Haochen Wang on 9/28/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit

public extension UIColor
{
    @inlinable
    @inline(__always)
    static func load(_ R: CGFloat, _ G: CGFloat, _ B: CGFloat, _ A: CGFloat = 1.0) -> UIColor
    {
        return UIColor(red: R / 255.0, green: G / 255.0, blue: B / 255.0, alpha: A)
    }
    
    @inlinable
    @inline(__always)
    static func hex(_ hex: UInt, _ A: CGFloat = 1.0) -> UIColor
    {
        let mask : Int = 0xFF
        let r = CGFloat(Int(hex >> 16) & mask)
        let g = CGFloat(Int(hex >> 8 ) & mask)
        let b = CGFloat(Int(hex      ) & mask)
        return load(r, g, b, A)
    }
    
    final class func hex(_ hexString: String, _ alpha: CGFloat = 1.0) -> UIColor
    {
        var hex : String = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard hex.count == 3 || hex.count == 6 else { return UIColor(white: 1.0, alpha: 0.0) }
        if hex.count == 3
        {
            for (index, char) in hex.enumerated()
            {
                hex.insert(char, at: hex.index(hex.startIndex, offsetBy: index * 2))
            }
        }
        return .hex(UInt(hex, radix: 16)!, alpha)
    }
}

public extension UIColor
{
    final var redValue: CGFloat { return rgba().r }
    final var greenValue: CGFloat { return rgba().g }
    final var blueValue: CGFloat { return rgba().b }
    final var alphaValue: CGFloat { return rgba().a }
    
    private final func rgba() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    {
        let components: [CGFloat]? = cgColor.components
        let numberOfComponents: Int = cgColor.numberOfComponents
        switch numberOfComponents {
        case 4:
            return (components![0], components![1], components![2], components![3])
        case 2:
            return (components![0], components![0], components![0], components![1])
        default:
            return (0, 0, 0, 1)
        }
    }
    
    fileprivate final var isDark: Bool { get { return (0.2126 * redValue + 0.7152 * greenValue + 0.0722 * blueValue) < 0.5 } }
    
    fileprivate final var isBlackOrWhite: Bool { get { return (redValue > 0.91 && greenValue > 0.91 && blueValue > 0.91) || (redValue < 0.09 && greenValue < 0.09 && blueValue < 0.09) } }
    
    fileprivate final func color(minSaturation: CGFloat) -> UIColor
    {
        var (hue, saturation, brightness, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        return saturation < minSaturation ? UIColor(hue: hue, saturation: minSaturation, brightness: brightness, alpha: alpha) : self
    }
    
    fileprivate final func isDistinct(from color: UIColor) -> Bool
    {
        let threshold: CGFloat = 0.25
        var result :Bool = false
        
        if abs(redValue - color.redValue) > threshold || abs(greenValue - color.greenValue) > threshold || abs(blueValue - color.blueValue) > threshold
        {
            if abs(redValue - greenValue) < 0.03 && abs(redValue - blueValue) < 0.03
            {
                if abs(color.redValue - color.greenValue) < 0.03 && abs(color.redValue - color.blueValue) < 0.03
                {
                    result = false
                }
            }
            result = true
        }
        return result
    }
    
    fileprivate final func isContrasting(with color: UIColor) -> Bool
    {
        let bgLum = 0.2126 * redValue + 0.7152 * greenValue + 0.0722 * blueValue
        let fgLum = 0.2126 * color.redValue + 0.7152 * color.greenValue + 0.0722 * color.blueValue
        let contrast = bgLum > fgLum ? (bgLum + 0.05) / (fgLum + 0.05) : (fgLum + 0.05) / (bgLum + 0.05)
        return 1.6 < contrast
    }
}

public extension UIImage
{
    final func colors(_ complete: ((_ background: UIColor, _ primary: UIColor, _ secondary: UIColor, _ detail: UIColor) -> Void)?)
    {
        Promise<(UIColor, UIColor, UIColor, UIColor)>.firstly { [weak self] (update, _) in
            
            guard let strongSelf = self else { return }
            update(strongSelf.getColors())
            
            }.then(on: .main) { (_, colors) in
                if let complete = complete, let colors = colors
                {
                    complete(colors.0, colors.1, colors.2, colors.3)
                }
            }.catch()
    }
    
    private final class CountedColor
    {
        let color: UIColor
        let count: Int
        
        init(color: UIColor, count: Int) {
            self.color = color
            self.count = count
        }
    }
    
    private final func getColors() -> (background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor)
    {
        let ratio: CGFloat = size.width / size.height
        let r_width: CGFloat = 250
        let cgImage: CGImage = reSize(to: CGSize(width: r_width, height: r_width / ratio)).cgImage!
        
        let width: Int = cgImage.width
        let height: Int = cgImage.height
        let bytesPerPixel: Int = 4
        let bytesPerRow: Int = width * bytesPerPixel
        let bitsPerComponent : Int = 8
        let randomColorsThreshold : Int = Int(CGFloat(height) * 0.01)
        let blackColor: UIColor = .black
        let whiteColor: UIColor = .white
        let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        let raw: UnsafeMutableRawPointer = malloc(bytesPerRow * height)
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue
        let context: CGContext? = CGContext(data: raw, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let data: UnsafePointer<UInt8>? = UnsafePointer<UInt8>(context?.data?.assumingMemoryBound(to: UInt8.self))
        let imageBackgroundColors: NSCountedSet = NSCountedSet(capacity: height)
        let imageColors: NSCountedSet = NSCountedSet(capacity: width * height)
        
        let sortComparator: (CountedColor, CountedColor) -> Bool = { (a, b) -> Bool in
          return a.count <= b.count
        }
        
        for x in 0..<width
        {
          for y in 0..<height
          {
            let pixel : Int = ((width * y) + x) * bytesPerPixel
            let color : UIColor = .load(CGFloat((data?[pixel+1])!), CGFloat((data?[pixel+2])!), CGFloat((data?[pixel+3])!))
            if x >= 5 && x <= 10
            {
              imageBackgroundColors.add(color)
            }
            
            imageColors.add(color)
          }
        }
        
        var sortedColors: [CountedColor] = []
        
        for (_, color) in imageBackgroundColors.enumerated()
        {
            guard let color = color as? UIColor else { continue }
            let colorCount: Int = imageBackgroundColors.count(for: color)
            if randomColorsThreshold <= colorCount
            {
                sortedColors.append(CountedColor(color: color, count: colorCount))
            }
        }
        
        sortedColors.sort(by: sortComparator)
        
        var proposedEdgeColor: CountedColor = .init(color: blackColor, count: 1)
        
        if let first = sortedColors.first { proposedEdgeColor = first }
        
        if proposedEdgeColor.color.isBlackOrWhite && !sortedColors.isEmpty
        {
          for countedColor in sortedColors where CGFloat(countedColor.count / proposedEdgeColor.count) > 0.3
          {
            if !countedColor.color.isBlackOrWhite
            {
              proposedEdgeColor = countedColor
              break
            }
          }
        }
        
        let imageBackgroundColor: UIColor = proposedEdgeColor.color
        let isDarkBackgound: Bool = imageBackgroundColor.isDark
        
        sortedColors.removeAll()
        
        for (_, imageColor) in imageColors.enumerated()
        {
          guard let imageColor = imageColor as? UIColor else { continue }
          let color = imageColor.color(minSaturation: 0.15)
          
          if color.isDark == (!isDarkBackgound)
          {
            let colorCount: Int = imageColors.count(for: color)
            sortedColors.append(CountedColor(color: color, count: colorCount))
          }
        }
        
        sortedColors.sort(by: sortComparator)
        
        var primaryColor, secondaryColor, detailColor: UIColor?
        
        for (_, countedColor) in sortedColors.enumerated()
        {
            let color: UIColor = countedColor.color
            if primaryColor == nil && color.isContrasting(with: imageBackgroundColor)
            {
                primaryColor = color
            }
            else if secondaryColor == nil && primaryColor != nil && primaryColor!.isDistinct(from: color) && color.isContrasting(with: imageBackgroundColor)
            {
                secondaryColor = color
            }
            else if secondaryColor != nil && (secondaryColor!.isDistinct(from: color) && primaryColor!.isDistinct(from: color) && color.isContrasting(with: imageBackgroundColor))
            {
                detailColor = color
                break
            }
        }
        
        free(raw)
        
        return (imageBackgroundColor, primaryColor ?? (isDarkBackgound ? whiteColor : blackColor), secondaryColor ?? (isDarkBackgound ? whiteColor : blackColor), detailColor ?? (isDarkBackgound ? whiteColor : blackColor))
    }
}
public extension UIColor
{
    final class var infoSystem: UIColor { get { return .load(47.0, 112.0, 225.0) } }
    final class var successSystem: UIColor { get { return .load(83.0, 215.0, 106.0) } }
    final class var warningSystem: UIColor { get { return .load(221.0, 170.0, 59.0) } }
    final class var dangerSystem: UIColor { get { return .load(229.0, 0.0, 15.0) } }
}

