//
//  CameraPreviewView.swift
//  LivenessMlKit
//

import SwiftUI
import AVFoundation
import Combine

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    init(session: AVCaptureSession) {
        self.session = session
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.liveness.cameraSessionQueue")
    @Published var isCameraAuthorized = false
    var currentPosition: AVCaptureDevice.Position = .front
    weak var analyzer: FaceDetectionAnalyzer?

    func checkPermission(analyzer: FaceDetectionAnalyzer? = nil) {
        if let analyzer = analyzer {
            self.analyzer = analyzer
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.isCameraAuthorized = true
            }
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isCameraAuthorized = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isCameraAuthorized = false
            }
        }
    }

    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Remove existing inputs
            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            // Camera device input
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            // Video output
            if self.session.canAddOutput(self.videoOutput) {
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.session.addOutput(self.videoOutput)
            }

            // Attach analyzer delegate
            if let analyzer = self.analyzer {
                self.videoOutput.setSampleBufferDelegate(analyzer, queue: DispatchQueue(label: "com.liveness.videoQueue"))
            }

            self.session.commitConfiguration()
            self.session.startRunning()
            print("📷 [CameraManager] Started capture session on position: \(self.currentPosition.rawValue)")
        }
    }

    func setAnalyzer(_ analyzer: FaceDetectionAnalyzer) {
        self.analyzer = analyzer
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.videoOutput.setSampleBufferDelegate(analyzer, queue: DispatchQueue(label: "com.liveness.videoQueue"))
            print("📷 [CameraManager] Attached sampleBufferDelegate to analyzer")
        }
    }

    func switchCamera(analyzer: FaceDetectionAnalyzer? = nil) {
        if let analyzer = analyzer {
            self.analyzer = analyzer
        }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()

            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            self.currentPosition = (self.currentPosition == .front) ? .back : .front
            self.analyzer?.cameraPosition = self.currentPosition

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            self.session.commitConfiguration()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}
