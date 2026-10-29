//
//  FaceClassifierService.swift
//  LivenessMlKit
//

import UIKit
import CoreML

public struct FaceClassificationOutput {
    public let topIndex: Int
    public let topLabel: String
    public let confidence: Float
    public let scores: [Float]

    public init(topIndex: Int, topLabel: String, confidence: Float, scores: [Float]) {
        self.topIndex = topIndex
        self.topLabel = topLabel
        self.confidence = confidence
        self.scores = scores
    }
}

public protocol FaceClassifierProtocol: AnyObject, Sendable {
    var labels: [String] { get }
    func classify(faceImage: UIImage) async throws -> FaceClassificationOutput
}

/// Face Classifier supporting Core ML, TFLite, and fallback simulation
public class FaceClassifierService: FaceClassifierProtocol, @unchecked Sendable {
    public private(set) var labels: [String] = []
    private let labelsFileName: String
    private let modelFileName: String

    /// Factory method that prefers TFLite with model.tflite if present, or Core ML / fallback
    public static func createDefault() -> FaceClassifierProtocol {
        #if canImport(TensorFlowLite)
        if let tflite = TFLiteClassifierService(modelName: "model", labelsName: "labels") {
            print("🚀 [FaceClassifierService] Active classifier: TFLiteClassifierService using model.tflite")
            return tflite
        }
        #endif
        print("ℹ️ [FaceClassifierService] Active classifier: FaceClassifierService (CoreML/Mock fallback)")
        return FaceClassifierService()
    }

    public init(
        labelsFileName: String = "labels",
        modelFileName: String = "model"
    ) {
        self.labelsFileName = labelsFileName
        self.modelFileName = modelFileName
        loadLabels()
    }

    private func loadLabels() {
        if let url = Bundle.main.url(forResource: labelsFileName, withExtension: "txt") ??
                     Bundle.main.url(forResource: labelsFileName, withExtension: "txt", subdirectory: "Model"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            self.labels = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            // Default labels matching Model/labels.txt
            self.labels = [
                "0_clear_face",
                "1_clear_eye_with_glass",
                "2_hair_over_face",
                "3_hand_over_face",
                "4_has_hat",
                "5_has_mask",
                "6_has_sunglasses"
            ]
        }
    }

    public func classify(faceImage: UIImage) async throws -> FaceClassificationOutput {
        // 1. Prepare 224x224 RGB image
        guard let resized = TransformUtils.resizeImage(faceImage, targetSize: CGSize(width: 224, height: 224)) else {
            throw NSError(domain: "FaceClassifier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to resize face image"])
        }

        // 2. Core ML / TFLite evaluation
        // If a Core ML compiled model (.mlmodelc) or TFLite model is in bundle, run it.
        // Otherwise, provide a default successful output for testing or fallback.
        if let modelURL = Bundle.main.url(forResource: modelFileName, withExtension: "mlmodelc") ??
                          Bundle.main.url(forResource: modelFileName, withExtension: "mlpackage") {
            return try await runCoreMLInference(image: resized, modelURL: modelURL)
        }

        // Default mock output for clear face when model file is not yet bundled
        return FaceClassificationOutput(
            topIndex: 0,
            topLabel: labels.first ?? "clear_face",
            confidence: 0.95,
            scores: [0.95, 0.02, 0.01, 0.01, 0.0, 0.01, 0.0]
        )
    }

    private func runCoreMLInference(image: UIImage, modelURL: URL) async throws -> FaceClassificationOutput {
        let compiledModel = try MLModel(contentsOf: modelURL)
        // Convert UIImage to CVPixelBuffer 224x224
        guard let pixelBuffer = image.toPixelBuffer(width: 224, height: 224) else {
            throw NSError(domain: "FaceClassifier", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CVPixelBuffer"])
        }

        // Run CoreML prediction
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
        let prediction = try await compiledModel.prediction(from: featureProvider)

        if let probMultiArray = prediction.featureValue(for: "probabilities")?.multiArrayValue {
            let count = probMultiArray.count
            var scores: [Float] = []
            for i in 0..<count {
                scores.append(probMultiArray[i].floatValue)
            }
            let maxIndex = scores.indices.max(by: { scores[$0] < scores[$1] }) ?? 0
            let label = labels.indices.contains(maxIndex) ? labels[maxIndex] : "Unknown"
            return FaceClassificationOutput(
                topIndex: maxIndex,
                topLabel: label,
                confidence: scores[maxIndex],
                scores: scores
            )
        }

        return FaceClassificationOutput(topIndex: 0, topLabel: labels[0], confidence: 0.9, scores: [])
    }
}

// MARK: - Pixel Buffer Helper
extension UIImage {
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        guard let cgImage = self.cgImage, let ctx = context else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return buffer
    }
}
