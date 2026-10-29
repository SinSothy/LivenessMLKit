//
//  ScanFaceLivenessVM.swift
//  LivenessMlKit
//

import UIKit
import CoreMedia
import Combine

#if canImport(MLKitFaceDetection)
import MLKitFaceDetection
#endif

@MainActor
public class ScanFaceLivenessVM: ObservableObject, FaceDetectionCallback {

    // MARK: - Published UI States
    @Published public var faceResult: FaceValidationResult?
    @Published public var resizedImageBitmap: UIImage?
    @Published public var faceLivenessAnalyze: FaceLivenessAnalyze?
    @Published public var isAnalyzing: Bool = false
    @Published public var isFaceDetected: Bool = false

    // MARK: - Configuration & Thresholds
    private var requireStableFrames: Int = 8
    private var requireStableFailFrames: Int = 3
    private var successCount: Int = 0
    private var errorCount: Int = 0
    private var failCount: Int = 0
    private var lastErrorType: Int?

    // MARK: - Liveness Tracking State
    private var lastLeftEyeOpen: Bool = false
    private var lastRightEyeOpen: Bool = false
    private var lastHeadEulerY: CGFloat = 0.0
    private var lastHeadEulerX: CGFloat = 0.0
    private var blinkDetected: Bool = false
    private var headMoved: Bool = false
    private var frameCount: Int = 0

    // MARK: - Classifier Service
    private let classifier: FaceClassifierProtocol

    public init(classifier: FaceClassifierProtocol) {
        self.classifier = classifier
    }

    public convenience init() {
        self.init(classifier: FaceClassifierService.createDefault())
    }

    // MARK: - Face Detection Callback Implementation
    #if canImport(MLKitFaceDetection)
    public func onSuccess(faces: [Face], sampleBuffer: CMSampleBuffer) {
        onSuccessFaces(results: faces, sampleBuffer: sampleBuffer)
    }
    #else
    public func onSuccess(faces: [Any], sampleBuffer: CMSampleBuffer) {
        // Fallback placeholder when MLKit framework is not yet imported
    }
    #endif

    public func onFailure(error: Error) {
        print("Face detection failed with error: \(error.localizedDescription)")
        if self.isFaceDetected {
            self.isFaceDetected = false
        }
    }

    // MARK: - Core Face Analysis Lifecycle
    #if canImport(MLKitFaceDetection)
    public func onSuccessFaces(results: [Face], sampleBuffer: CMSampleBuffer) {
        frameCount += 1

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))

        // 1. Check if face is detected
        if results.isEmpty {
            if self.isFaceDetected {
                self.isFaceDetected = false
            }
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_UNKNOWN,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_UNKNOWN,
                    message: "No face detected",
                    boundingBox: nil
                )
            )
            return
        }

        if !self.isFaceDetected {
            self.isFaceDetected = true
        }

        // 2. Only one face allowed
        if results.count != 1 {
            let firstBox = results.first?.frame
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_FAILED,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_FAILED,
                    message: "Please show only one face",
                    boundingBox: firstBox
                )
            )
            return
        }

        guard let face = results.first else { return }
        let box = face.frame

        // 3. Full face inside frame boundary check
        if box.minX < 0 || box.minY < 0 || box.maxX > width || box.maxY > height {
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_NOT_FULL_FRAME,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_NOT_FULL_FRAME,
                    message: "Please keep your full face in frame",
                    boundingBox: box
                )
            )
            return
        }

        // 4. Face size / distance check (face coverage ratio)
        let faceCoverage = box.width / width
        if faceCoverage < 0.3 {
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_FAR_FROM_FRAME,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_FAR_FROM_FRAME,
                    message: "Move closer to the camera",
                    boundingBox: box
                )
            )
            return
        }

        // 5. Lighting / Brightness check
        let brightness = TransformUtils.estimateBrightness(from: sampleBuffer)
        if brightness < 40 {
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_BRIGHTNESS_BRIGHT,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_BRIGHTNESS_BRIGHT,
                    message: "Too dark, please move to brighter light",
                    boundingBox: box
                )
            )
            return
        } else if brightness > 220 {
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_BRIGHTNESS_DARK,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_BRIGHTNESS_DARK,
                    message: "Too bright, reduce lighting",
                    boundingBox: box
                )
            )
            return
        }

        // 6. Eyes open detection
        let leftEyeOpen = face.hasLeftEyeOpenProbability && face.leftEyeOpenProbability > 0.3
        let rightEyeOpen = face.hasRightEyeOpenProbability && face.rightEyeOpenProbability > 0.3
        if !leftEyeOpen && !rightEyeOpen {
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_EYE_CLOSE,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_EYE_CLOSE,
                    message: "Please open your eyes",
                    boundingBox: box
                )
            )
            return
        }

        // 7. Liveness blink detection (sampled every 5 frames)
        if frameCount % 5 == 0 {
            if (lastLeftEyeOpen && !leftEyeOpen) || (lastRightEyeOpen && !rightEyeOpen) {
                blinkDetected = true
            }
            lastLeftEyeOpen = leftEyeOpen
            lastRightEyeOpen = rightEyeOpen
        }

        // 8. Natural head movement check (sampled every 10 frames)
        let rotY = abs(face.headEulerAngleY)
        let rotX = abs(face.headEulerAngleX)
        let headDeltaY = abs(rotY - lastHeadEulerY)
        let headDeltaX = abs(rotX - lastHeadEulerX)

        if frameCount % 10 == 0 {
            if headDeltaY > 3.0 || headDeltaX > 3.0 {
                headMoved = true
            }
            lastHeadEulerY = rotY
            lastHeadEulerX = rotX
        }

        // 9. Face orientation check
        if rotY > 20.0 || rotX > 20.0 {
            _ = emitStableResult(
                isValid: false,
                errorType: FaceValidationResult.FACE_ORIENTATION,
                result: .inValid(
                    actionType: FaceValidationResult.FACE_ORIENTATION,
                    message: "Please face straight at the camera",
                    boundingBox: box
                )
            )
            return
        }

        // 10. Run Face Attribute Classification (Hat, Mask, Hair, Sunglasses, etc.)
        analyzeImage(face: face, sampleBuffer: sampleBuffer, boundingBox: box)
    }

    public func analyzeImage(
        face: Face,
        sampleBuffer: CMSampleBuffer,
        boundingBox: CGRect
    ) {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        Task {
            defer { self.isAnalyzing = false }

            // 1. Convert sampleBuffer to UIImage
            guard let fullImage = TransformUtils.imageFromSampleBuffer(sampleBuffer) else { return }

            // 2. Expand bounding box (to include forehead, hair, and chin)
            let expandedBox = TransformUtils.scaleBoundingBox(
                box: boundingBox,
                imageWidth: fullImage.size.width,
                imageHeight: fullImage.size.height,
                expandTopRatio: 0.6,
                expandBottomRatio: 0.0,
                expandSideRatio: 0.4
            )

            // 3. Crop face region
            guard let croppedFace = TransformUtils.cropImage(fullImage, to: expandedBox) else { return }

            // 4. Zoom face (1.5x)
            let zoomedFace = TransformUtils.zoomImage(croppedFace, factor: 1.5) ?? croppedFace

            // 5. Resize to exact 224x224 pixels (1.0 scale) for ML model input
            guard let resizedFace = TransformUtils.resizeImage(zoomedFace, targetSize: CGSize(width: 224, height: 224)) else { return }
            self.resizedImageBitmap = resizedFace

            // 6. Run classification inference (TFLite or Core ML)
            do {
                let output = try await classifier.classify(faceImage: resizedFace)
                let topIndex = output.topIndex
                let topLabel = output.topLabel
                let confidence = output.confidence

                let classification = classifyFaceResult(labelIndex: topIndex)
                let isSuccess = classification.isSuccess
                let message = classification.message

                let analyzeResult = FaceLivenessAnalyze(
                    confidence: confidence,
                    topLabel: topLabel,
                    isBlinkDetected: self.blinkDetected,
                    message: message
                )
                self.faceLivenessAnalyze = analyzeResult

                if isSuccess {
                    self.successCount += 1
                    self.errorCount = 0

                    if self.blinkDetected || self.headMoved {
                        self.faceResult = .valid(
                            boundingBox: face.frame,
                            faceLivenessAnalyze: analyzeResult
                        )
                    } else {
                        // Face is valid, prompt user for liveness blink confirmation
                        self.faceResult = .inValid(
                            actionType: FaceValidationResult.FACE_NO_LIVENESS,
                            message: "\(message)\nPlease blink to confirm liveness",
                            boundingBox: face.frame
                        )
                    }
                } else {
                    self.successCount = 0
                    self.errorCount += 1

                    let statusList = [
                        FaceValidationResult.FACE_VALID,          // 0
                        FaceValidationResult.FACE_VALID,          // 1
                        FaceValidationResult.FACE_HAIR_OVER,       // 2
                        FaceValidationResult.FACE_HAND_OVER,       // 3
                        FaceValidationResult.FACE_HAS_HAT,         // 4
                        FaceValidationResult.FACE_HAS_MASK,        // 5
                        FaceValidationResult.FACE_HAS_SUNGLASSES   // 6
                    ]

                    let errorType = statusList.indices.contains(topIndex) ? statusList[topIndex] : FaceValidationResult.FACE_UNKNOWN

                    self.faceResult = .inValid(
                        actionType: errorType,
                        message: message,
                        boundingBox: face.frame
                    )
                }
            } catch {
                print("❌ [ScanFaceLivenessVM] Inference error: \(error.localizedDescription)")
            }
        }
    }
    #endif

    // MARK: - Classification Mapping
    public func classifyFaceResult(labelIndex: Int) -> (isSuccess: Bool, message: String) {
        switch labelIndex {
        case 0:
            return (true, "✅ Your face is clearly visible. Perfect!")
        case 1:
            return (true, "👓 Your face is clear with glasses. Looks good!")
        case 2:
            return (false, "💇 Please move your hair away so your face is visible.")
        case 3:
            return (false, "✋ Please move your hand away from your face.")
        case 4:
            return (false, "🧢 Please remove your hat so your face is fully visible.")
        case 5:
            return (false, "😷 Please remove your mask so we can see your face clearly.")
        case 6:
            return (false, "🕶️ Please take off your sunglasses for better recognition.")
        default:
            return (false, "⚠️ Face not recognized. Please try again.")
        }
    }

    // MARK: - Stable Frame Result Debouncing
    public func emitStableResult(
        isValid: Bool,
        errorType: Int?,
        result: FaceValidationResult
    ) -> Bool {
        if isValid {
            failCount = 0
            lastErrorType = nil
            successCount += 1

            if successCount >= requireStableFrames {
                faceResult = result
                return true
            } else {
                return false
            }
        } else {
            if lastErrorType == errorType {
                failCount += 1
            } else {
                failCount = 1
                lastErrorType = errorType
            }
            successCount = 0

            if failCount >= requireStableFailFrames {
                faceResult = result
                return true
            } else {
                return false
            }
        }
    }

    // MARK: - Reset State
    public func resetState() {
        frameCount = 0
        successCount = 0
        failCount = 0
        errorCount = 0
        lastErrorType = nil
        blinkDetected = false
        headMoved = false
        lastLeftEyeOpen = false
        lastRightEyeOpen = false
        lastHeadEulerY = 0.0
        lastHeadEulerX = 0.0
        faceResult = nil
        faceLivenessAnalyze = nil
        resizedImageBitmap = nil
        isAnalyzing = false
        isFaceDetected = false
    }
}
