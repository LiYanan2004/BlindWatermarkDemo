//
//  BitLoader.swift
//  HiddenWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/2.
//

import Foundation

class BitLoader {
    var data: Data { Data(bytes.prefix(byteIndex)) }
    
    private var bytes: [UInt8] = [0x00]
    private var byteIndex = 0 // 0 - inf
    private var bitIndex = 1 // 1 - 8
    
    func appendBit(_ bit: UInt8) {
        bytes[byteIndex] = (bytes[byteIndex] << 1) + (bit & 0x01)
        if bitIndex == 8 {
            bytes.append(0x00)
            bitIndex = 0
            byteIndex += 1
        }
        bitIndex += 1
    }
    
    func reset() {
        bytes = [0x00]
        bitIndex = 1
        byteIndex = 0
    }
}
