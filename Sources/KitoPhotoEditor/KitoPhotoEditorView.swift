//
//  KitoPhotoEditorView.swift
//  KitoPhotoEditor
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// A piece of text placed on the photo, as a fraction of its size measured from the photo's
/// top-left corner (the photo itself never mirrors, so neither does this, in any layout direction).
public struct KitoPhotoText: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var text: String
    public var position: CGPoint
    public var colorIndex: Int
    public var scale: CGFloat = 1

    static let palette: [Color] = [.white, .black, .yellow, .pink, .cyan, .orange]
}

/// Filters, adjustments, crop and text over one photo. Press and hold the photo to compare
/// with the original. `onDone` hands back the rendered result at full resolution.
public struct KitoPhotoEditorView: View {
    let original: UIImage
    let onCancel: () -> Void
    let onDone: (UIImage) -> Void

    enum Tool: String, CaseIterable, Identifiable {
        case filters = "Filters", adjust = "Adjust", crop = "Crop", text = "Text"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .filters: return "camera.filters"
            case .adjust: return "slider.horizontal.3"
            case .crop: return "crop.rotate"
            case .text: return "textformat"
            }
        }
    }

    enum Adjustment: String, CaseIterable, Identifiable {
        case exposure, brightness, contrast, saturation, warmth, vignette, sharpness, grain
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .exposure: return "plusminus.circle"
            case .brightness: return "sun.max"
            case .contrast: return "circle.lefthalf.filled"
            case .saturation: return "drop"
            case .warmth: return "thermometer.medium"
            case .vignette: return "circle.dashed"
            case .sharpness: return "triangle"
            case .grain: return "circle.grid.3x3"
            }
        }
        var range: ClosedRange<Double> { [.vignette, .sharpness, .grain].contains(self) ? 0...1 : -1...1 }
        var keyPath: WritableKeyPath<KitoPhotoAdjustments, Double> {
            switch self {
            case .exposure: return \.exposure
            case .brightness: return \.brightness
            case .contrast: return \.contrast
            case .saturation: return \.saturation
            case .warmth: return \.warmth
            case .vignette: return \.vignette
            case .sharpness: return \.sharpness
            case .grain: return \.grain
            }
        }
    }

    @State private var edit = KitoPhotoEdit()
    @State private var preview: UIImage?
    @State private var previewBase: UIImage
    @State private var thumbnails: [KitoPhotoFilter: UIImage] = [:]
    @State private var tool: Tool = .filters
    @State private var adjustment: Adjustment = .exposure
    @State private var comparing = false
    @State private var texts: [KitoPhotoText] = []
    @State private var draftText = ""
    @State private var isExporting = false
    @State private var renderTask: Task<Void, Never>?
    @Environment(\.layoutDirection) private var layoutDirection

    public init(image: UIImage, onCancel: @escaping () -> Void = {}, onDone: @escaping (UIImage) -> Void) {
        self.original = image
        self.onCancel = onCancel
        self.onDone = onDone
        _previewBase = State(initialValue: KitoPhotoRenderer.render(image, edit: KitoPhotoEdit(), maxDimension: 1400) ?? image)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            canvas.frame(maxHeight: .infinity)
            toolPanel.frame(height: 150)
            toolBar
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .onAppear { rerender(); makeThumbnails() }
        .onChange(of: edit) { _, _ in rerender() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel).font(.body)
            Spacer()
            Button {
                edit = KitoPhotoEdit()
                texts = []
            } label: { Text("Reset").font(.subheadline.weight(.semibold)) }
                .opacity(edit == KitoPhotoEdit() && texts.isEmpty ? 0.35 : 1)
                .disabled(edit == KitoPhotoEdit() && texts.isEmpty)
            Spacer()
            Button {
                export()
            } label: {
                if isExporting { ProgressView().tint(.black).frame(width: 60) } else { Text("Next").font(.headline).frame(width: 60) }
            }
            .padding(.vertical, 8)
            .background(Capsule().fill(.yellow))
            .foregroundStyle(.black)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let shown = comparing ? previewBase : (preview ?? previewBase)
            let fitted = Self.fit(shown.size, in: geometry.size)
            ZStack {
                Image(uiImage: shown).resizable().scaledToFit()
                    .frame(width: fitted.width, height: fitted.height)
                ForEach($texts) { $item in
                    Text(item.text)
                        .font(.system(size: 30 * item.scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(KitoPhotoText.palette[item.colorIndex % KitoPhotoText.palette.count])
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        // `position` mirrors in right-to-left layouts; the photo and the drag don't.
                        .position(x: (layoutDirection == .rightToLeft ? 1 - item.position.x : item.position.x) * fitted.width,
                                  y: item.position.y * fitted.height)
                        .gesture(DragGesture().onChanged { value in
                            item.position = CGPoint(x: min(max(value.location.x / fitted.width, 0.05), 0.95), y: min(max(value.location.y / fitted.height, 0.05), 0.95))
                        })
                        .onTapGesture { item.colorIndex += 1 }
                        .opacity(comparing ? 0 : 1)
                }
                .frame(width: fitted.width, height: fitted.height)
                if comparing {
                    Text("Original").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.15, perform: {}, onPressingChanged: { comparing = $0 })
            .animation(.easeOut(duration: 0.15), value: comparing)
        }
        .padding(.horizontal, 10)
        .accessibilityLabel("Photo preview. Press and hold to compare with the original.")
    }

    /// The largest size with `size`'s aspect ratio inside `bounds`.
    static func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: Tools

    @ViewBuilder
    private var toolPanel: some View {
        switch tool {
        case .filters: filterStrip
        case .adjust: adjustPanel
        case .crop: cropPanel
        case .text: textPanel
        }
    }

    private var filterStrip: some View {
        VStack(spacing: 12) {
            HStack {
                Text(edit.filter.name).font(.caption.bold())
                Slider(value: $edit.intensity, in: 0...1).tint(.yellow)
                Text("\(Int(edit.intensity * 100))").font(.caption.monospacedDigit()).frame(width: 30)
            }
            .padding(.horizontal, 20)
            .opacity(edit.filter == .original ? 0 : 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(KitoPhotoFilter.allCases) { filter in
                        Button { withAnimation(.snappy) { edit.filter = filter; if edit.intensity == 0 { edit.intensity = 1 } } } label: {
                            VStack(spacing: 6) {
                                Group {
                                    if let thumbnail = thumbnails[filter] { Image(uiImage: thumbnail).resizable().scaledToFill() } else { Color.white.opacity(0.1) }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(edit.filter == filter ? Color.yellow : .clear, lineWidth: 2.5))
                                Text(filter.name).font(.caption2.weight(edit.filter == filter ? .bold : .regular))
                                    .foregroundStyle(edit.filter == filter ? .yellow : .white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.name)
                        .accessibilityAddTraits(edit.filter == filter ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var adjustPanel: some View {
        VStack(spacing: 14) {
            let value = edit.adjustments[keyPath: adjustment.keyPath]
            HStack {
                Text(adjustment.name).font(.caption.bold())
                Slider(value: Binding(get: { edit.adjustments[keyPath: adjustment.keyPath] }, set: { edit.adjustments[keyPath: adjustment.keyPath] = $0 }), in: adjustment.range)
                    .tint(.yellow)
                Text("\(Int((value * 100).rounded()))").font(.caption.monospacedDigit()).frame(width: 36)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Adjustment.allCases) { item in
                        let changed = edit.adjustments[keyPath: item.keyPath] != 0
                        Button { adjustment = item } label: {
                            VStack(spacing: 6) {
                                Image(systemName: item.symbol).font(.title3)
                                    .frame(width: 52, height: 52)
                                    .background(Circle().stroke(adjustment == item ? Color.yellow : .white.opacity(0.25), lineWidth: 2))
                                    .overlay(alignment: .topTrailing) { if changed { Circle().fill(.yellow).frame(width: 8, height: 8) } }
                                Text(item.name).font(.caption2)
                            }
                            .foregroundStyle(adjustment == item ? .yellow : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var cropPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(KitoCropAspect.allCases) { aspect in
                    Button { withAnimation(.snappy) { edit.crop = aspect } } label: {
                        Text(aspect.name).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(edit.crop == aspect ? Color.yellow : .white.opacity(0.12)))
                            .foregroundStyle(edit.crop == aspect ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 40) {
                Button { edit.quarterTurns = (edit.quarterTurns + 3) % 4 } label: { Label("Rotate", systemImage: "rotate.left").labelStyle(.iconOnly).font(.title2) }
                    .accessibilityLabel("Rotate left")
                Button { edit.quarterTurns = (edit.quarterTurns + 1) % 4 } label: { Label("Rotate", systemImage: "rotate.right").labelStyle(.iconOnly).font(.title2) }
                    .accessibilityLabel("Rotate right")
                Button { edit.isFlipped.toggle() } label: { Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right").labelStyle(.iconOnly).font(.title2) }
                    .foregroundStyle(edit.isFlipped ? .yellow : .white)
                    .accessibilityLabel("Flip horizontally")
            }
        }
    }

    private var textPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField("Add text", text: $draftText)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .submitLabel(.done)
                    .onSubmit(addText)
                Button(action: addText) {
                    Image(systemName: "plus").font(.headline).frame(width: 44, height: 44).background(Circle().fill(.yellow)).foregroundStyle(.black)
                }
                .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add text")
            }
            .padding(.horizontal, 20)
            Text(texts.isEmpty ? "Type, then drag it into place. Tap text to change its colour." : "\(texts.count) on the photo · drag to move, tap to recolour")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            if !texts.isEmpty {
                Button("Remove last", role: .destructive) { texts.removeLast() }.font(.caption.weight(.semibold))
            }
        }
    }

    private var toolBar: some View {
        HStack {
            ForEach(Tool.allCases) { item in
                Button { withAnimation(.snappy) { tool = item } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.title3)
                        Text(item.rawValue).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tool == item ? .yellow : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Rendering

    private func addText() {
        let trimmed = draftText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        texts.append(KitoPhotoText(text: trimmed, position: CGPoint(x: 0.5, y: 0.5 + Double(texts.count % 4) * 0.08), colorIndex: texts.count))
        draftText = ""
    }

    private func rerender() {
        renderTask?.cancel()
        let base = previewBase
        let edit = edit
        renderTask = Task.detached(priority: .userInitiated) {
            let image = KitoPhotoRenderer.render(base, edit: edit)
            guard !Task.isCancelled else { return }
            await MainActor.run { preview = image }
        }
    }

    private func makeThumbnails() {
        let base = previewBase
        Task.detached(priority: .utility) {
            var results: [KitoPhotoFilter: UIImage] = [:]
            for filter in KitoPhotoFilter.allCases {
                var edit = KitoPhotoEdit()
                edit.filter = filter
                edit.crop = .square
                if let image = KitoPhotoRenderer.render(base, edit: edit, maxDimension: 160) { results[filter] = image }
            }
            let finished = results
            await MainActor.run { thumbnails = finished }
        }
    }

    private func export() {
        isExporting = true
        let original = original
        let edit = edit
        let texts = texts
        Task.detached(priority: .userInitiated) {
            let rendered = KitoPhotoRenderer.render(original, edit: edit) ?? original
            await MainActor.run {
                let final = texts.isEmpty ? rendered : Self.burn(texts, into: rendered)
                isExporting = false
                onDone(final)
            }
        }
    }

    /// Draws the text overlays into the image at full resolution.
    @MainActor
    static func burn(_ texts: [KitoPhotoText], into image: UIImage) -> UIImage {
        let size = image.size
        let base = min(size.width, size.height) / 340
        let scene = ZStack {
            Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
            ForEach(texts) { item in
                Text(item.text)
                    .font(.system(size: 30 * item.scale * base, weight: .heavy, design: .rounded))
                    .foregroundStyle(KitoPhotoText.palette[item.colorIndex % KitoPhotoText.palette.count])
                    .shadow(color: .black.opacity(0.4), radius: 4 * base, y: 2 * base)
                    .position(x: item.position.x * size.width, y: item.position.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: scene)
        renderer.scale = 1
        return renderer.uiImage ?? image
    }
}

// MARK: - Flow

/// Camera, then the editor. `onFinish` gets the edited photo; publishing is yours to add.
public struct KitoPhotoFlow: View {
    let onFinish: (UIImage) -> Void
    let onCancel: () -> Void
    @State private var captured: UIImage?

    public init(onFinish: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void = {}) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            if let captured {
                KitoPhotoEditorView(image: captured, onCancel: { withAnimation { self.captured = nil } }, onDone: onFinish)
                    .transition(.move(edge: .trailing))
            } else {
                KitoCameraView(onCapture: { image in withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { captured = image } }, onCancel: onCancel)
                    .transition(.move(edge: .leading))
            }
        }
    }
}
