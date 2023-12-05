//
//  TextWatermarkCanvas.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import SwiftUI

struct TextWatermarkCanvas: View {
    var text: String
    @Environment(\.displayScale) private var scale
    
    var body: some View {
        Canvas { context, size in
            context.fill(Rectangle().path(in: CGRect(origin: .zero, size: size)), with: .color(.white))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(45))
            
            let maxSide = max(size.width, size.height)
            let sideLength = 2 * sqrt(2) * maxSide
            let contentSize = CGSize(width: sideLength, height: sideLength)
            
            let renderer = ImageRenderer(content: Text(text).foregroundStyle(.black).padding(8))
            renderer.proposedSize = ProposedViewSize(contentSize)
            renderer.scale = scale
            
            if let cgImage = renderer.cgImage {
                let origin = CGPoint(x: -size.width, y: -size.height)
                context.fill(Rectangle().path(in: CGRect(origin: origin, size: contentSize)), with: .tiledImage(Image(decorative: cgImage, scale: scale)))
            }
        }
    }
}

#Preview {
    TextWatermarkCanvas(text: "SwiftUI")
}
