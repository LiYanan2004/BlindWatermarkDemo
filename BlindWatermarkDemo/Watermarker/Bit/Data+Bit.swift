//
//  Data+Bit.swift
//  HiddenWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/1.
//

import Foundation

extension Data {
    /// Load Data with bits.
    init(bits: [Int]) {
        var bytes: [UInt8] = [0x00]
        var bitIndex = 1
        var byteIndex = 0
        for bit in bits {
            bytes[byteIndex] = (bytes[byteIndex] << 1) + (UInt8(bit) & 0x01)
            if bitIndex == 8 {
                bytes.append(0x00)
                byteIndex += 1
                bitIndex = 0
            }
            bitIndex += 1
        }
        bytes[byteIndex] = bytes[byteIndex] << (8 - bitIndex + 1)
        self.init(bytes)
    }
}
