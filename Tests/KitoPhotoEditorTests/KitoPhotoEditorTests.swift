//
//  KitoPhotoEditorTests.swift
//  KitoPhotoEditor
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import SwiftUI
@testable import KitoPhotoEditor

final class KitoPhotoEditorTests: XCTestCase {
    private func solid(_ color: UIColor, size: CGSize = CGSize(width: 40, height: 20)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func centerPixel(_ image: UIImage) -> (r: Double, g: Double, b: Double) {
        guard let cgImage = image.cgImage else { return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cgImage, in: CGRect(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2,
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    func testUntouchedEditKeepsSize() throws {
        let output = try XCTUnwrap(KitoPhotoRenderer.render(solid(.gray), edit: KitoPhotoEdit()))
        XCTAssertEqual(output.size, CGSize(width: 40, height: 20))
    }

    func testEveryFilterRenders() {
        for filter in KitoPhotoFilter.allCases {
            var edit = KitoPhotoEdit()
            edit.filter = filter
            XCTAssertNotNil(KitoPhotoRenderer.render(solid(.orange), edit: edit), filter.name)
        }
    }

    func testWarmthWarmsAndCoolingCools() throws {
        var edit = KitoPhotoEdit()
        edit.adjustments.warmth = 1
        let warm = centerPixel(try XCTUnwrap(KitoPhotoRenderer.render(solid(.gray), edit: edit)))
        XCTAssertGreaterThan(warm.r, warm.b)
        edit.adjustments.warmth = -1
        let cool = centerPixel(try XCTUnwrap(KitoPhotoRenderer.render(solid(.gray), edit: edit)))
        XCTAssertGreaterThan(cool.b, cool.r)
    }

    func testMonoRemovesColour() throws {
        var edit = KitoPhotoEdit()
        edit.filter = .mono
        let pixel = centerPixel(try XCTUnwrap(KitoPhotoRenderer.render(solid(.red), edit: edit)))
        XCTAssertEqual(pixel.r, pixel.b, accuracy: 3)
    }

    func testZeroIntensityIsTheOriginal() throws {
        var edit = KitoPhotoEdit()
        edit.filter = .mono
        edit.intensity = 0
        let pixel = centerPixel(try XCTUnwrap(KitoPhotoRenderer.render(solid(.red), edit: edit)))
        XCTAssertGreaterThan(pixel.r, pixel.b + 100)
    }

    func testCropAspects() {
        let extent = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(KitoCropAspect.original.rect(in: extent), extent)
        XCTAssertEqual(KitoCropAspect.square.rect(in: extent), CGRect(x: 50, y: 0, width: 300, height: 300))
        let landscape = KitoCropAspect.landscape.rect(in: extent)
        XCTAssertEqual(landscape.width, 400)
        XCTAssertEqual(landscape.height, 225, accuracy: 0.01)
        XCTAssertEqual(landscape.midY, 150, accuracy: 0.01)
    }

    func testCropAndRotateChangeTheOutputSize() throws {
        var edit = KitoPhotoEdit()
        edit.crop = .square
        XCTAssertEqual(try XCTUnwrap(KitoPhotoRenderer.render(solid(.gray), edit: edit)).size, CGSize(width: 20, height: 20))
        edit.crop = .original
        edit.quarterTurns = 1
        XCTAssertEqual(try XCTUnwrap(KitoPhotoRenderer.render(solid(.gray), edit: edit)).size, CGSize(width: 20, height: 40))
    }

    func testMaxDimensionDownsizes() throws {
        let output = try XCTUnwrap(KitoPhotoRenderer.render(solid(.gray, size: CGSize(width: 1000, height: 500)), edit: KitoPhotoEdit(), maxDimension: 200))
        XCTAssertEqual(output.size, CGSize(width: 200, height: 100))
    }

    func testOrientationMapping() {
        XCTAssertEqual(KitoPhotoRenderer.orientation(quarterTurns: 0, flipped: false), .up)
        XCTAssertEqual(KitoPhotoRenderer.orientation(quarterTurns: 1, flipped: false), .right)
        XCTAssertEqual(KitoPhotoRenderer.orientation(quarterTurns: -1, flipped: false), .left)
        XCTAssertEqual(KitoPhotoRenderer.orientation(quarterTurns: 6, flipped: true), .downMirrored)
    }

    func testFit() {
        XCTAssertEqual(KitoPhotoEditorView.fit(CGSize(width: 400, height: 200), in: CGSize(width: 100, height: 100)), CGSize(width: 100, height: 50))
        XCTAssertEqual(KitoPhotoEditorView.fit(.zero, in: CGSize(width: 100, height: 100)), .zero)
    }

    @MainActor
    func testSamplePhotoAndBurnKeepSize() {
        let sample = KitoSamplePhoto.make(size: CGSize(width: 300, height: 400))
        XCTAssertEqual(sample.size.width / sample.size.height, 0.75, accuracy: 0.01)
        let burned = KitoPhotoEditorView.burn([KitoPhotoText(text: "Hi", position: CGPoint(x: 0.5, y: 0.5), colorIndex: 0)], into: solid(.gray, size: CGSize(width: 300, height: 200)))
        XCTAssertEqual(burned.size, CGSize(width: 300, height: 200))
    }
}
