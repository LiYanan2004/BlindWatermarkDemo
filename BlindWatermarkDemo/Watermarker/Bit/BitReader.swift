//
//  BitReader.swift
//  HiddenWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/1.
//

import Foundation

struct Bit: OptionSet {
    var rawValue: UInt8
    
    static let zero = Bit([])
    static let one  = Bit(rawValue: 1)
}


class BitReader {
    var data: [UInt8]
    
    private var byteIndex = 0 // 0 - inf
    private var bitIndex = 1 // 1 - 8
    private var byteCount: Int
    
    private var loopReading: Bool
    
    init(data: [UInt8], loop: Bool = false) {
        self.data = data
        self.byteCount = data.count
        self.loopReading = loop
    }
    
    init(data: Data, loop: Bool = false) {
        self.data = data.map { $0 }
        self.byteCount = data.count
        self.loopReading = loop
    }
    
    func nextBit() -> Bit? {
        guard byteCount > byteIndex else { return nil }
        defer {
            if bitIndex == 8 {
                if loopReading {
                    byteIndex = byteIndex + 1 == byteCount ? 0 : byteIndex + 1
                } else {
                    byteIndex += 1
                }
                bitIndex = 0
            }
            bitIndex += 1
        }
        return Bit(rawValue: ((data[byteIndex]) >> (8 - bitIndex)) & 0x01)
    }
    
    func nextBits(_ k: Int) -> [Bit] {
        (0..<k).compactMap { _ in
            nextBit()
        }
    }
    
    func allBits() -> [Bit] {
        byteIndex = 0
        bitIndex = 1
        return nextBits(byteCount * 8)
    }
}
