//
//  Empty+CGContext.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import CoreGraphics

extension CGContext {
    static func emptyContext(width: Int, height: Int) -> CGContext? {
        .init(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        )
    }
}
