//
//  KitoPhotoRenderer.swift
//  KitoPhotoEditor
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A one-tap look.
public enum KitoPhotoFilter: String, CaseIterable, Identifiable, Sendable {
    case original, vivid, warm, cool, mono, noir, fade, chrome, instant, dramatic, sepia, film

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .original: return "Original"
        case .vivid: return "Vivid"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .fade: return "Fade"
        case .chrome: return "Chrome"
        case .instant: return "Instant"
        case .dramatic: return "Dramatic"
        case .sepia: return "Sepia"
        case .film: return "Film"
        }
    }

    func apply(_ image: CIImage) -> CIImage {
        switch self {
        case .original:
            return image
        case .vivid:
            let vibrance = CIFilter.vibrance(); vibrance.inputImage = image; vibrance.amount = 0.8
            return KitoPhotoRenderer.colorControls(vibrance.outputImage ?? image, saturation: 1.12)
        case .warm:
            return KitoPhotoRenderer.temperature(image, warmth: 0.9)
        case .cool:
            return KitoPhotoRenderer.temperature(image, warmth: -0.9)
        case .mono:
            return KitoPhotoRenderer.effect("CIPhotoEffectMono", image)
        case .noir:
            return KitoPhotoRenderer.effect("CIPhotoEffectNoir", image)
        case .fade:
            return KitoPhotoRenderer.effect("CIPhotoEffectFade", image)
        case .chrome:
            return KitoPhotoRenderer.effect("CIPhotoEffectChrome", image)
        case .instant:
            return KitoPhotoRenderer.effect("CIPhotoEffectInstant", image)
        case .dramatic:
            let lifted = CIFilter.exposureAdjust(); lifted.inputImage = image; lifted.ev = 0.25
            return KitoPhotoRenderer.vignette(KitoPhotoRenderer.colorControls(lifted.outputImage ?? image, saturation: 0.85, contrast: 1.18), amount: 0.6)
        case .sepia:
            let sepia = CIFilter.sepiaTone(); sepia.inputImage = image; sepia.intensity = 0.85
            return sepia.outputImage ?? image
        case .film:
            return KitoPhotoRenderer.grain(KitoPhotoRenderer.effect("CIPhotoEffectTransfer", image), amount: 0.5)
        }
    }
}

/// Fine-tuning on top of a filter. Every value is 0 when untouched; the ranges are -1...1
/// (brightness, contrast, saturation, exposure, warmth) or 0...1 (vignette, sharpness, grain).
public struct KitoPhotoAdjustments: Equatable, Sendable {
    public var brightness: Double = 0
    public var contrast: Double = 0
    public var saturation: Double = 0
    public var exposure: Double = 0
    public var warmth: Double = 0
    public var vignette: Double = 0
    public var sharpness: Double = 0
    public var grain: Double = 0

    public init() {}

    public var isIdentity: Bool { self == KitoPhotoAdjustments() }
}

/// The frame's shape after cropping, centred.
public enum KitoCropAspect: String, CaseIterable, Identifiable, Sendable {
    case original, square, portrait, landscape, story

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .original: return "Original"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .landscape: return "16:9"
        case .story: return "9:16"
        }
    }

    /// Width over height, or nil to keep the photo's own.
    public var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .landscape: return 16.0 / 9.0
        case .story: return 9.0 / 16.0
        }
    }

    /// The largest centred rect of this ratio inside `extent`.
    public func rect(in extent: CGRect) -> CGRect {
        guard let ratio, extent.width > 0, extent.height > 0 else { return extent }
        let current = extent.width / extent.height
        if current > ratio {
            let width = extent.height * ratio
            return CGRect(x: extent.midX - width / 2, y: extent.minY, width: width, height: extent.height)
        } else {
            let height = extent.width / ratio
            return CGRect(x: extent.minX, y: extent.midY - height / 2, width: extent.width, height: height)
        }
    }
}

/// Everything an edit is: the look, its strength, the fine-tuning and the geometry.
public struct KitoPhotoEdit: Equatable, Sendable {
    public var filter: KitoPhotoFilter = .original
    /// 0...1: how much of the filter shows over the original.
    public var intensity: Double = 1
    public var adjustments = KitoPhotoAdjustments()
    public var crop: KitoCropAspect = .original
    /// Clockwise quarter turns, 0...3.
    public var quarterTurns: Int = 0
    public var isFlipped = false

    public init() {}
}

/// Renders a `KitoPhotoEdit` with Core Image on one shared context.
public enum KitoPhotoRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// The edited photo. `maxDimension` downsizes first, for fast previews and thumbnails.
    public static func render(_ image: UIImage, edit: KitoPhotoEdit, maxDimension: CGFloat? = nil) -> UIImage? {
        guard var input = ciImage(from: image, maxDimension: maxDimension) else { return nil }
        let original = input

        if edit.filter != .original, edit.intensity > 0 {
            let filtered = edit.filter.apply(input).cropped(to: original.extent)
            input = blend(filtered, over: original, amount: edit.intensity)
        }
        input = adjust(input, edit.adjustments).cropped(to: original.extent)
        input = input.cropped(to: edit.crop.rect(in: input.extent))
        input = input.oriented(orientation(quarterTurns: edit.quarterTurns, flipped: edit.isFlipped))
        input = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))

        guard let cgImage = context.createCGImage(input, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Upright, optionally downsized: camera photos carry an orientation Core Image ignores.
    static func ciImage(from image: UIImage, maxDimension: CGFloat?) -> CIImage? {
        let longest = max(image.size.width, image.size.height)
        let scale = maxDimension.map { min($0 / max(longest, 1), 1) } ?? 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return upright.cgImage.map { CIImage(cgImage: $0) }
    }

    static func orientation(quarterTurns: Int, flipped: Bool) -> CGImagePropertyOrientation {
        switch (((quarterTurns % 4) + 4) % 4, flipped) {
        case (0, false): return .up
        case (1, false): return .right
        case (2, false): return .down
        case (3, false): return .left
        case (0, true): return .upMirrored
        case (1, true): return .rightMirrored
        case (2, true): return .downMirrored
        default: return .leftMirrored
        }
    }

    // MARK: Building blocks

    static func blend(_ top: CIImage, over bottom: CIImage, amount: Double) -> CIImage {
        guard amount < 1 else { return top }
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = bottom
        dissolve.targetImage = top
        dissolve.time = Float(min(max(amount, 0), 1))
        return dissolve.outputImage ?? top
    }

    static func adjust(_ image: CIImage, _ a: KitoPhotoAdjustments) -> CIImage {
        guard !a.isIdentity else { return image }
        var output = image
        if a.exposure != 0 {
            let exposure = CIFilter.exposureAdjust(); exposure.inputImage = output; exposure.ev = Float(a.exposure * 1.5)
            output = exposure.outputImage ?? output
        }
        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            output = colorControls(output, saturation: 1 + a.saturation, contrast: 1 + a.contrast * 0.5, brightness: a.brightness * 0.25)
        }
        if a.warmth != 0 { output = temperature(output, warmth: a.warmth) }
        if a.sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance(); sharpen.inputImage = output; sharpen.sharpness = Float(a.sharpness * 1.2)
            output = sharpen.outputImage ?? output
        }
        if a.vignette > 0 { output = vignette(output, amount: a.vignette) }
        if a.grain > 0 { output = grain(output, amount: a.grain) }
        return output
    }

    static func colorControls(_ image: CIImage, saturation: Double = 1, contrast: Double = 1, brightness: Double = 0) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = Float(saturation)
        controls.contrast = Float(contrast)
        controls.brightness = Float(brightness)
        return controls.outputImage ?? image
    }

    /// -1 cool … 1 warm.
    static func temperature(_ image: CIImage, warmth: Double) -> CIImage {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500, y: 0)
        filter.targetNeutral = CIVector(x: 6500 - warmth * 2500, y: 0)
        return filter.outputImage ?? image
    }

    static func vignette(_ image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.vignette()
        filter.inputImage = image
        filter.intensity = Float(amount * 1.6)
        filter.radius = Float(max(image.extent.width, image.extent.height) / 900)
        return filter.outputImage ?? image
    }

    static func grain(_ image: CIImage, amount: Double) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        let alpha = CGFloat(amount * 0.12)
        mono.rVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        mono.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        mono.bVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: alpha)
        mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard let speckle = mono.outputImage?.cropped(to: image.extent) else { return image }
        let composite = CIFilter.overlayBlendMode()
        composite.inputImage = speckle
        composite.backgroundImage = image
        return composite.outputImage?.cropped(to: image.extent) ?? image
    }

    static func effect(_ name: String, _ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }
}
