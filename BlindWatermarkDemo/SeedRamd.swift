//
//  SeedRamd.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import Foundation

struct SeedRamd: RandomNumberGenerator {
    private var seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
    }

    mutating func next() -> UInt64 {
        seed = (seed &* 1664525) &+ 1013904223
        return seed
    }
}
