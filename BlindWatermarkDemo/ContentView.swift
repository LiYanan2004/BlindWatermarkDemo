//
//  ContentView.swift
//  BlindWatermarkDemo
//
//  Created by LiYanan2004 on 2023/8/12.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // State
    @State private var originalImage: PlatformImage?
    @State private var watermarkedImage: PlatformImage?
    @State private var dropTargetted = false
    @State private var watermarkContent = ""
    @State private var showTextField = false
    
    @State private var showWatermarkView = false
    @State private var watermark: PlatformImage?
    
    var body: some View {
        NavigationStack {
            HStack {
                ZStack {
                    if let originalImage {
                        Rectangle()
                            .overlay {
                                Image(platformImage: originalImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundStyle(.quaternary)
                            Text("Drag a photo here.").font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.blue, lineWidth: 3.0)
                        .opacity(dropTargetted ? 1 : 0)
                }
                .onDrop(of: [.image], isTargeted: $dropTargetted) { providers in
                    _ = providers.first?.loadDataRepresentation(for: .image) { data, _ in
                        guard let data else { return }
                        if let platformImage = PlatformImage(data: data) {
                            self.originalImage = platformImage
                        }
                    }
                    return true
                }
                
                ZStack {
                    if let watermarkedImage {
                        Rectangle()
                            .overlay {
                                Image(platformImage: watermarkedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundStyle(.quaternary)
                            Text("Drag a photo here.").font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.blue, lineWidth: 3.0)
                        .opacity(dropTargetted ? 1 : 0)
                }
                .onDrop(of: [.image], isTargeted: $dropTargetted) { providers in
                    _ = providers.first?.loadDataRepresentation(for: .image) { data, _ in
                        guard let data else { return }
                        if let watermarkedImage = PlatformImage(data: data) {
                            self.watermarkedImage = watermarkedImage
                        }
                    }
                    return true
                }
            }
            .toolbar(content: toolbarContent)
            .scenePadding()
            .inspector(isPresented: $showWatermarkView) {
                if let watermark {
                    Image(platformImage: watermark)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .inspectorColumnWidth(ideal: 600, max: 800)
                }
            }
        }
    }
    
    private func addWatermark() {
        let renderedImage = Task<CGImage?, Never> { @MainActor in
            guard let originalImage else { return nil }
            let renderer = ImageRenderer(content: TextWatermarkCanvas(text: watermarkContent))
            renderer.proposedSize = ProposedViewSize(width: CGFloat(Int(originalImage.size.width).next2n()), height: CGFloat(Int(originalImage.size.height / 2).next2n()))
            renderer.scale = 1
            
            return renderer.cgImage
        }
        Task {
            // let fftImage = ImageWatermarker(image: originalImage!.cgImage!).fftImage()
            let wmImage = ImageWatermarker.addWatermark(await renderedImage.value!, to: originalImage!.cgImage!)
            guard let wmImage else { return }
            #if canImport(UIKit)
            self.wmImage = PlatformImage(cgImage: wmImage)
            #elseif canImport(AppKit)
            self.watermarkedImage = PlatformImage(cgImage: wmImage, size: .zero)
            #endif
        }
    }
    
    private func extractWatermark() {
        Task {
            guard let originalImage else { return }
            guard let watermarkedImage else { return }
            guard let watermark = ImageWatermarker.extractWatermark(watermarkedImage.cgImage!, originalImage: originalImage.cgImage!) else { return }
            #if canImport(UIKit)
            self.watermark = PlatformImage(cgImage: watermark)
            #elseif canImport(AppKit)
            self.watermark = PlatformImage(cgImage: watermark, size: .zero)
            #endif
            showWatermarkView = true
        }
    }
}

// MARK: - Toolbar Contents

extension ContentView {
    @ToolbarContentBuilder
    func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                let image = Image(platformImage: watermarkedImage ?? PlatformImage())
                ShareLink(
                    item: image,
                    preview: SharePreview(Text("Photo"), image: image)
                )
                .disabled(originalImage == nil)
            }
            Button {
                showTextField = true
            } label: {
                Label("Watermark", systemImage: "water.waves")
            }
            .disabled(originalImage == nil)
            .popover(isPresented: $showTextField, arrowEdge: .bottom) {
                VStack(spacing: 20) {
                    TextField("Watermark Content", text: $watermarkContent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit {
                            showTextField = false
                            addWatermark()
                        }
                    Button {
                        showTextField = false
                        addWatermark()
                    } label: {
                        Text("Add Watermark").padding(4)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .controlSize(.large)
            }
            
            Button(action: extractWatermark) {
                Label("Extract Watermark", systemImage: "water.waves.slash")
            }
            .disabled(originalImage == nil)
        }
    }
}

#Preview {
    ContentView()
}
