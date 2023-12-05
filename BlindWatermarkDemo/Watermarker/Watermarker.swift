//
//  Watermarker.swift
//  HiddenWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/2.
//

import SwiftUI
import UniformTypeIdentifiers

enum Watermarker {
    
    // - MARK: - Watermark Image & Return `CGImage`
    
    static func markImage(
        _ image: PlatformImage,
        text: String,
        progress: ((Double) -> Void)? = nil
    ) async -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        return await _watermark(cgImage: cgImage, text: text, progress: progress)
    }
    
    static func markImage(
        _ image: CGImage,
        text: String,
        progress: ((Double) -> Void)? = nil
    ) async -> CGImage? {
        await _watermark(cgImage: image, text: text, progress: progress)
    }
    
    // - MARK: - Watermark Image & Save to disk
    
    @discardableResult
    static func markImageAndSave(
        _ image: CGImage,
        destinationPath: String,
        text: String,
        progress: ((Double) -> Void)? = nil
    ) async -> Bool {
        guard let wmImage = await _watermark(cgImage: image, text: text, progress: progress) else {
            return false
        }
        let destinationURL = URL(fileURLWithPath: destinationPath) as CFURL
        if let destination = CGImageDestinationCreateWithURL(destinationURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, wmImage, nil)
            CGImageDestinationFinalize(destination)
            return true
        }
        return false
    }
    
    @discardableResult
    static func markImageAndSave(
        _ image: PlatformImage,
        destinationPath: String,
        text: String,
        progress: ((Double) -> Void)? = nil
    ) async -> Bool {
        guard let cgImage = image.cgImage,
              let wmImage = await _watermark(cgImage: cgImage, text: text, progress: progress) else {
            return false
        }
        let destinationURL = URL(fileURLWithPath: destinationPath) as CFURL
        if let destination = CGImageDestinationCreateWithURL(destinationURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, wmImage, nil)
            CGImageDestinationFinalize(destination)
            return true
        }
        return false
    }
   
    // - MARK: - Extract watermark from a photo
    
    static func extract(
        _ image: PlatformImage,
        progress: ((Double) -> Void)? = nil
    ) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await _extractWatermark(cgImage: cgImage, progress: progress)
    }
    
    static func extract(
        _ image: CGImage,
        progress: ((Double) -> Void)? = nil
    ) async -> String? {
        await _extractWatermark(cgImage: image, progress: progress)
    }
}

// - MARK: Internals

extension Watermarker {
    private static func _watermark(cgImage: CGImage, text: String, progress: ((Double) -> Void)?) async -> CGImage? {
        if let context = Self.bitmapContext(from: cgImage),
           let data = context.data {
            let width = cgImage.width
            let height = cgImage.height
            let buffer = data.assumingMemoryBound(to: UInt32.self)
            
            let bits = BitReader(data: [0x00, UInt8(text.count)] + text.data(using: .utf8)!, loop: true)
                .allBits()
                .map { $0.rawValue }
            let msgBitCount = bits.count
            var _progress = 0.0
            let _progressP = withUnsafeMutablePointer(to: &_progress) { $0 }
            await withTaskGroup(of: Void.self) { group in
                for y in 0..<height {
                    group.addTask {
                        for x in 0..<width {
                            let pos = y * width + x
                            let rgba = buffer[pos]
                            
                            guard rgba & 0xff != 0 else { continue }
                            
                            var r = UInt8((rgba >> 24) & 0xff)
                            var g = UInt8((rgba >> 16) & 0xff)
                            var b = UInt8((rgba >>  8) & 0xff)
                            
                            let mask: UInt8 = 0x01
                            
                            let baseOffset = pos * 3
                            r = ((r - (r & mask)) + bits[(baseOffset + 0) % msgBitCount])
                            g = ((g - (g & mask)) + bits[(baseOffset + 1) % msgBitCount])
                            b = ((b - (b & mask)) + bits[(baseOffset + 2) % msgBitCount])
                            
                            buffer[pos] = (UInt32(r) << 24) | (UInt32(g) << 16) | (UInt32(b) << 8) | UInt32(rgba & 0xff)
                        }
                        _progressP.pointee += 1.0 / Double(height)
                        progress?(_progressP.pointee)
                    }
                }
            }
            return context.makeImage()
        }
        return nil
    }
    
    private static func _extractWatermark(cgImage: CGImage, progress: ((Double) -> Void)?) async -> String? {
        if let context = Self.bitmapContext(from: cgImage),
           let data = context.data {
            let width = cgImage.width
            let height = cgImage.height
            let buffer = data.assumingMemoryBound(to: UInt32.self)
            let bitLoader = BitLoader()
            
            for y in 0..<height {
                for x in 0..<width {
                    let pos = y * width + x
                    let rgba = buffer[pos]
                    
                    guard rgba & 0xff != 0 else { continue }
                    
                    let r = UInt8((rgba >> 24) & 0xff)
                    let g = UInt8((rgba >> 16) & 0xff)
                    let b = UInt8((rgba >>  8) & 0xff)
                    
                    let mask: UInt8 = 0x01
                    
                    bitLoader.appendBit(r & mask)
                    bitLoader.appendBit(g & mask)
                    bitLoader.appendBit(b & mask)
                    
                    var data = bitLoader.data
                    if let index = data.firstIndex(of: 0x00) {
                        data = data.dropFirst(index + 1)
                        if let length = data.first {
                            let messageData = data.prefix(Int(length) + 1)
                            if messageData.count == Int(length) + 1 {
                                progress?(1.0)
                                return String(decoding: messageData.dropFirst(), as: UTF8.self)
                            }
                        }
                    }
                }
                progress?(Double(y + 1) / Double(height))
            }
        }
        
        return nil
    }
    
    private static func bitmapContext(from image: CGImage) -> CGContext? {
        let width = image.width
        let height = image.height
        
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        return context
    }
}
