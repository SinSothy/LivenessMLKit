//
//  FaceDetectionAnalyzer.swift
//  LivenessMlKit
//

import UIKit
import AVFoundation

#if canImport(MLKitFaceDetection)
import MLKitFaceDetection
import MLKitVision
#endif

// MARK: - Face Detection Callback Protocol
protocol FaceDetectionCallback: AnyObject {
    #if canImport(MLKitFaceDetection)
    func onSuccess(faces: [Face], sampleBuffer: CMSampleBuffer)
    #else
    func onSuccess(faces: [Any], sampleBuffer: CMSampleBuffer)
    #endif
    func onFailure(error: Error)
}

// MARK: - Face Detection Analyzer
class FaceDetectionAnalyzer: NSObject {

    weak var callback: FaceDetectionCallback?
    var cameraPosition: AVCaptureDevice.Position = .front
    private let processingQueue = DispatchQueue(label: "com.liveness.faceAnalyzerQueue", qos: .userInitiated)
    private var isBusy = false

    #if canImport(MLKitFaceDetection)
    private lazy var detector: FaceDetector = {
        let options = FaceDetectorOptions()
        options.performanceMode = .accurate
        options.landmarkMode = .all
        options.contourMode = .all
        options.classificationMode = .all
        options.minFaceSize = 0.15
        options.isTrackingEnabled = true
        return FaceDetector.faceDetector(options: options)
    }()
    #endif

    init(callback: FaceDetectionCallback? = nil) {
        self.callback = callback
        super.init()
    }

    func analyze(sampleBuffer: CMSampleBuffer) {
        guard !isBusy else { return }
        isBusy = true

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isBusy = false }

            #if canImport(MLKitFaceDetection)
            let visionImage = VisionImage(buffer: sampleBuffer)
            visionImage.orientation = self.imageOrientation()

            do {
                let faces = try self.detector.results(in: visionImage)
                DispatchQueue.main.async {
                    self.callback?.onSuccess(faces: faces, sampleBuffer: sampleBuffer)
                }
            } catch {
                print("❌ [FaceDetectionAnalyzer] Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.callback?.onFailure(error: error)
                }
            }
            #else
            DispatchQueue.main.async {
                self.callback?.onSuccess(faces: [], sampleBuffer: sampleBuffer)
            }
            #endif
        }
    }

    public func stop() {
    }

    private func imageOrientation() -> UIImage.Orientation {
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .portrait:
            return cameraPosition == .front ? .leftMirrored : .right
        case .landscapeLeft:
            return cameraPosition == .front ? .downMirrored : .up
        case .landscapeRight:
            return cameraPosition == .front ? .upMirrored : .down
        case .portraitUpsideDown:
            return cameraPosition == .front ? .rightMirrored : .down
        default:
            return cameraPosition == .front ? .leftMirrored : .right
        }
    }

    // MARK: - Face Evaluation Logic
    #if canImport(MLKitFaceDetection)
    static func evaluateFaces(
        faces: [Face],
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        onResult: (FaceResult) -> Void
    ) {
        var faceResult = FaceResult()

        if faces.isEmpty {
            faceResult.message = "No face detected"
            onResult(faceResult)
            return
        }

        if faces.count > 1 {
            faceResult.message = "Only one face allowed"
            onResult(faceResult)
            return
        }

        let face = faces[0]

        if !isFullFaceVisible(face) {
            faceResult.detected = true
            faceResult.message = "Show your full face"
            onResult(faceResult)
            return
        }

        let box = face.frame
        let faceAreaRatio = (box.width * box.height) / (frameWidth * frameHeight)
        let centerX = box.midX / frameWidth
        let centerY = box.midY / frameHeight
        let isCentered = (0.3...0.7).contains(centerX) && (0.25...0.75).contains(centerY)

        if faceAreaRatio < 0.12 {
            faceResult.detected = true
            faceResult.message = "Move closer"
            onResult(faceResult)
        } else if faceAreaRatio > 0.55 {
            faceResult.detected = true
            faceResult.message = "Move back"
            onResult(faceResult)
        } else if !isCentered {
            faceResult.detected = true
            faceResult.message = "Center your face"
            onResult(faceResult)
        } else {
            faceResult.detected = true
            faceResult.canCapture = true
            faceResult.message = "Ready to capture"
            onResult(faceResult)
        }
    }

    static func isFullFaceVisible(_ face: Face) -> Bool {
        let requiredLandmarks: [FaceLandmarkType] = [
            .leftEye, .rightEye, .noseBase,
            .mouthLeft, .mouthRight, .mouthBottom,
            .leftEar, .rightEar, .leftCheek, .rightCheek
        ]

        let allPresent = requiredLandmarks.allSatisfy { face.landmark(ofType: $0) != nil }
        guard allPresent else { return false }

        let yaw = face.headEulerAngleY
        let pitch = face.headEulerAngleX

        return abs(yaw) < 20.0 && abs(pitch) < 20.0
    }
    #endif
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension FaceDetectionAnalyzer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        analyze(sampleBuffer: sampleBuffer)
    }
}
