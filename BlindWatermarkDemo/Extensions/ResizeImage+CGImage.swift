//
//  ResizeImage+CGImage.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import CoreGraphics

extension CGImage {
    func resizeImage(width: Int, height: Int) -> CGImage? {
        let (originWidth, originHeight) = (self.width, self.height)
        
        let originContext = CGContext.emptyContext(width: originWidth, height: originHeight)
        originContext?.draw(self, in: CGRect(origin: .zero, size: CGSize(width: originWidth, height: originHeight)))
        let originBuf = originContext?.data?.assumingMemoryBound(to: UInt32.self)
        guard let originBuf else { return nil }
        
        let resizedContext = CGContext.emptyContext(width: width, height: height)
        let resizedBuf = resizedContext?.data?.assumingMemoryBound(to: UInt32.self)
        guard let resizedBuf else { return nil }
        
        for y in 0..<height {
            if y > originHeight - 1 {
                continue
            }
            for x in 0..<width {
                if x > originWidth - 1 {
                    continue
                }
                let originPos = y * originWidth + x
                let resizedPos = y * width + x
                resizedBuf[resizedPos] = originBuf[originPos]
            }
        }
        
        return resizedContext!.makeImage()
    }
}


