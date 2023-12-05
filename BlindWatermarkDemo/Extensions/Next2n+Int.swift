//
//  Next2n+Int.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import Foundation

extension Int {
    func next2n() -> Int {
        1 << Int(ceil(log2(Float(self))))
    }
}
