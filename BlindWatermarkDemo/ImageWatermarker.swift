//
//  ImageWatermarker.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import Accelerate
import Foundation

class ImageWatermarker {
    private var fftSetUp: vDSP.FFT2D<DSPDoubleSplitComplex>
    
    private var alpha: Double = 10
    private var image: CGImage
    private var (originalWidth, originalHeight): (Int, Int)
    
    var (width, height): (Int, Int)
    private var (r, g, b): ([Double], [Double], [Double])
    
    init(image: CGImage) {
        (originalWidth, originalHeight) = (image.width, image.height)
        (width, height) = (image.width.next2n(), image.height.next2n())
        let resizedImage = image.resizeImage(width: width, height: height)
        
        self.fftSetUp = vDSP.FFT2D(width: width, height: height, ofType: DSPDoubleSplitComplex.self)!
        self.image = resizedImage!
        
        let pixelCount = width * height
        (r, g, b) = (
            [Double](repeating: 0, count: pixelCount),
            [Double](repeating: 0, count: pixelCount),
            [Double](repeating: 0, count: pixelCount)
        )
    }
    
    func addImageWatermark(_ watermark: CGImage) -> CGImage? {
        // Transform original image using fft2d.
        perform3ChannelFFT(r: &r, g: &g, b: &b)
        
        // Randomly encode watermark image
        let matrix = encodeWatermark(watermark, seed: 1024)
        
        // Mix watermark matrixes into 3 channels, namely RGB.
        // Tested on macOS Sonoma beta, but in the final stable release, there is a crash.
        // Still investigating...
        vDSP.add(multiplication: (matrix, alpha), multiplication: (r, 1), result: &r)
        vDSP.add(multiplication: (matrix, alpha), multiplication: (g, 1), result: &g)
        vDSP.add(multiplication: (matrix, alpha), multiplication: (b, 1), result: &b)
        
        // Perform IFFT to turn it back to RGB data.
        performFFT(r, direction: .inverse, result: &r)
        performFFT(g, direction: .inverse, result: &g)
        performFFT(b, direction: .inverse, result: &b)
        
        // Make image from RGB channels.
        return makeImageFromRGB()?.resizeImage(width: originalWidth, height: originalHeight)
    }
    
    func extractWatermark(originalImage: CGImage) -> CGImage? {
        // Transform watermarked image using fft2d.
        perform3ChannelFFT(r: &r, g: &g, b: &b)
        
        // Transform original image using fft2d.
        let originalImageWatermarker = ImageWatermarker(image: originalImage)
        let originPixelCount = originalImageWatermarker.width * originalImageWatermarker.height
        var (or, og, ob) = (
            [Double](repeating: 0, count: originPixelCount),
            [Double](repeating: 0, count: originPixelCount),
            [Double](repeating: 0, count: originPixelCount)
        )
        originalImageWatermarker.perform3ChannelFFT(r: &or, g: &og, b: &ob)
        
        // Calculate delta between the two.
        let (dr, dg, db) = (
            delta(&r, &or, scale: 1.0 / alpha),
            delta(&g, &og, scale: 1.0 / alpha),
            delta(&b, &ob, scale: 1.0 / alpha)
        )
        var delta = vDSP.add(multiplication: (dr, 1), multiplication: (dg, 1))
        vDSP.add(multiplication: (delta, 1.0), multiplication: (db, 1), result: &delta)
        vDSP.multiply(1.0 / 3.0, delta, result: &delta)
        
        // Make random matrix buffer.
        let max = log(9e-3 * vDSP.maximum(delta) + 1.0)
        let matrixContext = CGContext.emptyContext(width: originalImage.width, height: originalImage.height)!
        let messyBuf = matrixContext.data!.assumingMemoryBound(to: UInt32.self)
        for y in 0..<originalImage.height {
            for x in 0..<originalImage.width {
                let pos = y * originalImage.width + x
                let rgb = log(9e-3 * delta[pos] + 1.0)
                let channel = UInt32(UInt32(rgb / max * 255.0) & 0xff)
                messyBuf[pos] = UInt32(channel << 24 | channel << 16 | channel << 8 | UInt32(255))
            }
        }
        
        // Decode buffer into watermark image.
        return decodeWatermark(messyBuf: messyBuf, seed: 1024)
    }
}

// MARK: - FFT Methods

extension ImageWatermarker {
    private func perform3ChannelFFT(r: inout [Double], g: inout [Double], b: inout [Double]) {
        var cgImageFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 3,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        )!
        let sourceBuffer = try! vImage.PixelBuffer(
            cgImage: image,
            cgImageFormat: &cgImageFormat,
            pixelFormat: vImage.Interleaved8x3.self
        )
        
        let channels = sourceBuffer.planarBuffers()
        let pixelCount = width * height
        r = [Double](repeating: 0, count: pixelCount)
        g = [Double](repeating: 0, count: pixelCount)
        b = [Double](repeating: 0, count: pixelCount)
        
        vDSP.convertElements(of: channels[0].array, to: &r)
        vDSP.convertElements(of: channels[1].array, to: &g)
        vDSP.convertElements(of: channels[2].array, to: &b)
        
        performFFT(r, result: &r)
        performFFT(g, result: &g)
        performFFT(b, result: &b)
    }
    
    private func performFFT(_ signals: [Double], direction: vDSP.FourierTransformDirection = .forward, result: inout [Double]) {
        var signals = signals
        let complexValuesCount = signals.count / 2
        
        var inputReal = [Double](repeating: 0, count: complexValuesCount)
        var inputImag = [Double](repeating: 0, count: complexValuesCount)
        var input = inputReal.withUnsafeMutableBufferPointer { inputRealPtr in
            inputImag.withUnsafeMutableBufferPointer { inputImagPtr in
                DSPDoubleSplitComplex(
                    realp: inputRealPtr.baseAddress!,
                    imagp: inputImagPtr.baseAddress!
                )
            }
        }
        
        signals.withUnsafeMutableBufferPointer { p in
            p.withMemoryRebound(to: DSPDoubleComplex.self) {
                vDSP_ctozD([DSPDoubleComplex]($0), 2, &input, 1, vDSP_Length(complexValuesCount))
            }
        }
        
        var outputReal = [Double](repeating: 0, count: complexValuesCount)
        var outputImag = [Double](repeating: 0, count: complexValuesCount)
        var output = outputReal.withUnsafeMutableBufferPointer { outputRealPtr in
            outputImag.withUnsafeMutableBufferPointer { outputImagPtr in
                DSPDoubleSplitComplex(
                    realp: outputRealPtr.baseAddress!,
                    imagp: outputImagPtr.baseAddress!
                )
            }
        }
        
        fftSetUp.transform(
            input: input,
            output: &output,
            direction: direction
        )
        
        result.withUnsafeMutableBufferPointer { resultPtr in
            let complexPtr = UnsafeMutableRawPointer(resultPtr.baseAddress!).assumingMemoryBound(to: DSPDoubleComplex.self)
            vDSP_ztocD(&output, 1, complexPtr, 2, vDSP_Length(complexValuesCount))
        }
    }
}

// MARK: -  Watermark Encoder & Decoder

extension ImageWatermarker {
    private func encodeWatermark(_ watermarkImage: CGImage, seed: UInt64) -> [Double] {
        assert(watermarkImage.width <= originalWidth, "The width of watermark image must be smaller than the original's.")
        assert(watermarkImage.height / 2 <= originalWidth, "The half height of watermark image must be smaller than the original's.")
        var matrix = [Double](repeating: 0, count: originalWidth * originalHeight)
        var order = [Int](repeating: 0, count: originalWidth * originalHeight / 2)
        var random = [Int](repeating: 0, count: originalWidth * originalHeight / 2)
        
        for i in 0..<originalWidth * originalHeight / 2 {
            order[i] = i
        }
        
        var randomGenerator = SeedRamd(seed: seed)
        var count = originalWidth * originalHeight / 2
        while count > 0 {
            let index = Int.random(in: 0 ..< Int.max, using: &randomGenerator) % count
            random[originalWidth * originalHeight / 2 - count] = order[index]
            order[index] = order[count - 1]
            count -= 1
        }
        
        let context = CGContext.emptyContext(width: watermarkImage.width, height: watermarkImage.height)!
        context.draw(watermarkImage, in: CGRect(origin: .zero, size: CGSize(width: watermarkImage.width, height: watermarkImage.height)))
        let buf = context.data!.assumingMemoryBound(to: UInt32.self)
        
        for y in 0..<watermarkImage.height {
            for x in 0..<watermarkImage.width {
                let pos = y * watermarkImage.width + x
                let r = Int((buf[pos] >> 24) & 0xff)
                let g = Int((buf[pos] >> 16) & 0xff)
                let b = Int((buf[pos] >>  8) & 0xff)
                let adjustedRgb = 255.0 - Double(r + g + b) / 3.0
                
                matrix[random[y * originalWidth + x]] = adjustedRgb
                matrix[originalWidth * originalHeight - random[y * originalWidth + x] - 1] = adjustedRgb
            }
        }
        
        return matrix
    }

    private func decodeWatermark(messyBuf: UnsafeMutablePointer<UInt32>, seed: UInt64) -> CGImage? {
        var order = [Int](repeating: 0, count: width * height / 2)
        var random = [Int](repeating: 0, count: width * height / 2)
        
        for i in 0..<width * height / 2 {
            order[i] = i
        }

        var randomGenerator = SeedRamd(seed: seed)
        var count = width * height / 2
        while count > 0 {
            let index = Int.random(in: 0 ..< Int.max, using: &randomGenerator) % count
            random[width * height / 2 - count] = order[index]
            order[index] = order[count - 1]
            count -= 1
        }
        
        var realQueue = [Int](repeating: 0, count: width * height / 2)
        for i in 0..<(width * height / 2) {
            realQueue[random[i]] = i
        }
        
        let context = CGContext.emptyContext(width: width, height: height)!
        let imageBuf = context.data!.assumingMemoryBound(to: UInt32.self)
        
        for i in 0..<(width * height / 2) {
            let r = (messyBuf[i] >> 24) & 0xff
            let g = (messyBuf[i] >> 16) & 0xff
            let b = (messyBuf[i] >>  8) & 0xff
            
            let color = UInt32(UInt32(r << 24) | UInt32(g << 16) | UInt32(b << 8) | UInt32(255))
            imageBuf[realQueue[i]] = color
            imageBuf[width * height - realQueue[i] - 1] = color
        }
        
        return context.makeImage()!
    }
}

// MARK: - Helper Methods

extension ImageWatermarker {
    private func fftImage(_ channel: [Double]) -> CGImage? {
        var channel = channel
        let scale = 1 / Double(width * height * 2)
        vDSP.multiply(scale, channel, result: &channel)
        
        let context = CGContext.emptyContext(width: width, height: height)
        let buffer = context?.data?.assumingMemoryBound(to: UInt32.self)
        guard let buffer else { return nil }
        
        for y in 0..<height {
            for x in 0..<width {
                let pos = y * width + x
                let r = UInt32(abs(Int(channel[pos])) & 0xff) << 24
                let g = UInt32(abs(Int(channel[pos])) & 0xff) << 16
                let b = UInt32(abs(Int(channel[pos])) & 0xff) <<  8
                buffer[pos] = r | g | b | UInt32(255)
            }
        }
        
        return context!.makeImage()
    }
    
    private func makeImageFromRGB() -> CGImage? {
        let scale = 1 / Double(width * height * 2)
        vDSP.multiply(scale, r, result: &r)
        vDSP.multiply(scale, g, result: &g)
        vDSP.multiply(scale, b, result: &b)
        
        let context = CGContext.emptyContext(width: width, height: height)
        let buffer = context?.data?.assumingMemoryBound(to: UInt32.self)
        guard let buffer else { return nil }
        
        for y in 0..<height {
            for x in 0..<width {
                let pos = y * width + x
                let r = UInt32(abs(Int(r[pos])) & 0xff) << 24
                let g = UInt32(abs(Int(g[pos])) & 0xff) << 16
                let b = UInt32(abs(Int(b[pos])) & 0xff) <<  8
                buffer[pos] = r | g | b | UInt32(255)
            }
        }
        
        return context!.makeImage()
    }
    
    private func delta(_ a: inout [Double], _ b: inout [Double], scale: Double) -> [Double] {
        var delta = vDSP.add(multiplication: (a, 1.0), multiplication: (b, -1.0))
        vDSP.absolute(delta, result: &delta)
        vDSP.multiply(scale, delta, result: &delta)
        return delta
    }
}

// MARK: - Draw FFT Spectrum Image

extension ImageWatermarker {
    func fftImage() -> CGImage? {
        perform3ChannelFFT(r: &r, g: &g, b: &b)
        
        let context = CGContext.emptyContext(width: width, height: height)
        let buf = context?.data?.assumingMemoryBound(to: UInt32.self)
        guard let buf else { return nil }
        
        let logOfMaxMagR = maxRadius(r)
        let logOfMaxMagG = maxRadius(g)
        let logOfMaxMagB = maxRadius(b)
           
        for i in 0..<(width * height) {
            let r = colorValue(logOfMaxMag: logOfMaxMagR, channelSignal: r[i])
            let g = colorValue(logOfMaxMag: logOfMaxMagG, channelSignal: g[i])
            let b = colorValue(logOfMaxMag: logOfMaxMagB, channelSignal: b[i])
            
            let color = UInt32(UInt32(r << 24) | UInt32(g << 16) | UInt32(b << 8) | UInt32(255))
            buf[i] = color
        }
        
        return context!.makeImage()
    }
    
    private func maxRadius(_ channel: [Double]) -> Double {
        let maxRadius = vDSP.maximum(channel)
        return log(9e-3 * maxRadius + 1.0)
    }
    
    private func colorValue(logOfMaxMag: Double, channelSignal: Double) -> UInt8 {
        let color = log(9e-3 * abs(channelSignal) + 1.0)
        return UInt8(Int(round(255.0 * (color / logOfMaxMag))) & 0xff)
    }
}

extension ImageWatermarker {
    static func addWatermark(_ watermark: CGImage, to originalImage: CGImage) -> CGImage? {
        let marker = ImageWatermarker(image: originalImage)
        return marker.addImageWatermark(watermark)
    }
    
    static func extractWatermark(_ watermarkedImage: CGImage, originalImage: CGImage) -> CGImage? {
        let extractor = ImageWatermarker(image: watermarkedImage)
        return extractor.extractWatermark(originalImage: originalImage)
    }
}
