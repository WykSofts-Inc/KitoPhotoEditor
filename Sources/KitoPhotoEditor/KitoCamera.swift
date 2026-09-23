//
//  KitoCamera.swift
//  KitoPhotoEditor
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
@preconcurrency import AVFoundation

/// Drives an `AVCaptureSession` for stills: permission, front/back, flash, zoom and capture.
/// Needs `NSCameraUsageDescription` in the app's Info.plist.
@MainActor
@Observable
public final class KitoCameraModel: NSObject {
    public enum Status: Equatable { case idle, running, denied, unavailable }
    public enum Flash: String, CaseIterable { case off, auto, on
        var avMode: AVCaptureDevice.FlashMode { switch self { case .off: return .off; case .auto: return .auto; case .on: return .on } }
        var symbol: String { switch self { case .off: return "bolt.slash.fill"; case .auto: return "bolt.badge.automatic.fill"; case .on: return "bolt.fill" } }
    }

    public private(set) var status: Status = .idle
    public private(set) var position: AVCaptureDevice.Position = .back
    public var flash: Flash = .off
    public private(set) var zoom: CGFloat = 1
    public private(set) var isCapturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private let queue = DispatchQueue(label: "kito.camera.session")
    private var continuation: CheckedContinuation<UIImage?, Never>?

    public override init() {}

    /// Asks for permission if needed, then starts the preview.
    public func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        default:
            status = .denied
            return
        }
        guard configure(position: position) else { status = .unavailable; return }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
        status = .running
    }

    public func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    public func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        if configure(position: next) { position = next; zoom = 1 }
    }

    public func cycleFlash() {
        let all = Flash.allCases
        flash = all[(all.firstIndex(of: flash)! + 1) % all.count]
    }

    /// Sets the zoom factor, clamped to what the lens allows.
    public func setZoom(_ factor: CGFloat) {
        guard let device = input?.device else { return }
        let clamped = min(max(factor, device.minAvailableVideoZoomFactor), min(device.maxAvailableVideoZoomFactor, 8))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            zoom = clamped
        } catch {}
    }

    /// Takes a photo.
    public func capture() async -> UIImage? {
        guard status == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(flash.avMode) { settings.flashMode = flash.avMode }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else { session.commitConfiguration(); return false }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        return true
    }
}

extension KitoCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            let mirrored = self.position == .front ? image.map { UIImage(cgImage: $0.cgImage!, scale: $0.scale, orientation: .leftMirrored) } : image
            self.continuation?.resume(returning: mirrored)
            self.continuation = nil
        }
    }
}

/// The live camera feed.
struct KitoCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// A full-screen camera: live preview, shutter, flip, flash, grid and zoom. Where there's no
/// camera (the Simulator) or access is denied, it offers a sample photo instead.
public struct KitoCameraView: View {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var camera = KitoCameraModel()
    @State private var showsGrid = false
    @State private var flashOverlay = false
    @State private var pinchBase: CGFloat = 1

    public init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void = {}) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ZStack {
                    viewfinder
                    if showsGrid { KitoGridOverlay().allowsHitTesting(false) }
                    Color.white.opacity(flashOverlay ? 0.85 : 0).allowsHitTesting(false)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 8)
                Spacer(minLength: 12)
                zoomPicker
                controls.padding(.vertical, 22)
            }
        }
        .foregroundStyle(.white)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var viewfinder: some View {
        switch camera.status {
        case .running:
            KitoCameraPreview(session: camera.session)
                .gesture(MagnifyGesture().onChanged { camera.setZoom(pinchBase * $0.magnification) }.onEnded { _ in pinchBase = camera.zoom })
        case .idle:
            ProgressView().tint(.white)
        case .denied, .unavailable:
            VStack(spacing: 14) {
                Image(systemName: camera.status == .denied ? "lock.fill" : "camera.fill").font(.largeTitle)
                Text(camera.status == .denied ? "Camera access is off" : "No camera here").font(.headline)
                Text(camera.status == .denied ? "Turn it on in Settings, or try a sample photo." : "Try the editor with a sample photo.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                Button("Use a sample photo") { onCapture(KitoSamplePhoto.make()) }
                    .font(.headline).padding(.horizontal, 20).padding(.vertical, 12).background(Capsule().fill(.white)).foregroundStyle(.black)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onCancel) { Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Close camera")
            Spacer()
            Button { camera.cycleFlash() } label: { Image(systemName: camera.flash.symbol).font(.title3).frame(width: 44, height: 44) }
                .foregroundStyle(camera.flash == .off ? .white : .yellow)
                .accessibilityLabel("Flash \(camera.flash.rawValue)")
            Button { withAnimation { showsGrid.toggle() } } label: { Image(systemName: "grid").font(.title3).frame(width: 44, height: 44) }
                .foregroundStyle(showsGrid ? .yellow : .white)
                .accessibilityLabel(showsGrid ? "Hide grid" : "Show grid")
        }
        .padding(.horizontal, 12)
    }

    private var zoomPicker: some View {
        HStack(spacing: 10) {
            ForEach([0.5, 1.0, 2.0], id: \.self) { factor in
                Button { camera.setZoom(factor); pinchBase = camera.zoom } label: {
                    Text(factor == 0.5 ? ".5" : "\(Int(factor))×")
                        .font(.caption.weight(.bold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .foregroundStyle(abs(camera.zoom - factor) < 0.05 ? .yellow : .white)
                }
            }
        }
        .opacity(camera.status == .running ? 1 : 0)
    }

    private var controls: some View {
        HStack {
            Color.clear.frame(width: 56, height: 56)
            Spacer()
            Button {
                Task {
                    withAnimation(.easeOut(duration: 0.08)) { flashOverlay = true }
                    let photo = await camera.capture()
                    withAnimation(.easeIn(duration: 0.25)) { flashOverlay = false }
                    if let photo { onCapture(photo) }
                }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(.white).frame(width: camera.isCapturing ? 56 : 64, height: camera.isCapturing ? 56 : 64)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: camera.isCapturing)
            }
            .disabled(camera.status != .running)
            .accessibilityLabel("Take photo")
            Spacer()
            Button { withAnimation(.spring) { camera.flip() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.title2).frame(width: 56, height: 56).background(Circle().fill(.white.opacity(0.15)))
            }
            .disabled(camera.status != .running)
            .accessibilityLabel("Switch camera")
        }
        .padding(.horizontal, 30)
    }
}

/// Rule-of-thirds lines.
struct KitoGridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for fraction in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0)); path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction)); path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 0.8)
        }
    }
}

/// A generated landscape for trying the editor without a camera: sky, sun, hills and a lake.
public enum KitoSamplePhoto {
    @MainActor
    public static func make(size: CGSize = CGSize(width: 1200, height: 1600)) -> UIImage {
        let scene = ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.9), Color(red: 0.98, green: 0.72, blue: 0.52)], startPoint: .top, endPoint: .center)
            Circle().fill(Color(red: 1, green: 0.85, blue: 0.55)).frame(width: size.width * 0.28).blur(radius: 4).offset(x: size.width * 0.18, y: -size.height * 0.12)
            KitoHill(peak: 0.35, depth: 0.52).fill(Color(red: 0.32, green: 0.36, blue: 0.55))
            KitoHill(peak: 0.7, depth: 0.6).fill(Color(red: 0.22, green: 0.3, blue: 0.38))
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.62), Color(red: 0.1, green: 0.22, blue: 0.3)], startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 0.3)
            }
            KitoHill(peak: 0.15, depth: 0.78).fill(Color(red: 0.12, green: 0.2, blue: 0.14))
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: scene)
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }
}

struct KitoHill: Shape {
    let peak: CGFloat
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            let base = rect.height * depth
            path.move(to: CGPoint(x: 0, y: base))
            path.addCurve(to: CGPoint(x: rect.width, y: base + rect.height * 0.05),
                          control1: CGPoint(x: rect.width * peak, y: base - rect.height * 0.22),
                          control2: CGPoint(x: rect.width * (peak + 0.2), y: base - rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}
