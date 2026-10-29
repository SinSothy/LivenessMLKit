//
//  TFLiteClassifierService.swift
//  LivenessMlKit
//

import UIKit

#if canImport(TensorFlowLite)
import TensorFlowLite

/// Direct TensorFlow Lite Classifier matching Android's Interpreter usage
public class TFLiteClassifierService: FaceClassifierProtocol, @unchecked Sendable {
    public private(set) var labels: [String] = []
    private var interpreter: Interpreter?

    private var inputWidth: Int = 224
    private var inputHeight: Int = 224
    private var inputChannels: Int = 3

    public convenience init?(modelName: String = "model", labelsName: String = "labels") {
        guard let modelURL = TFLiteClassifierService.findModelURL(name: modelName) else {
            print("❌ [TFLiteClassifierService] Could not locate \(modelName).tflite in Bundle.")
            return nil
        }
        let labelsURL = TFLiteClassifierService.findLabelsURL(name: labelsName)
        self.init(modelPath: modelURL.path, labelsPath: labelsURL?.path ?? "")
    }

    public init(modelPath: String, labelsPath: String) {
        loadLabels(labelsPath: labelsPath)
        setupInterpreter(modelPath: modelPath)
    }

    public static func findModelURL(name: String = "model") -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "tflite") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "tflite", subdirectory: "Model") {
            return url
        }
        if let url = Bundle.main.urls(forResourcesWithExtension: "tflite", subdirectory: nil)?.first {
            return url
        }
        // Fallback search in all bundle subdirectories
        if let resourcePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                for case let file as String in enumerator {
                    if file.hasSuffix("\(name).tflite") || file.hasSuffix(".tflite") {
                        return URL(fileURLWithPath: (resourcePath as NSString).appendingPathComponent(file))
                    }
                }
            }
        }
        return nil
    }

    public static func findLabelsURL(name: String = "labels") -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "txt") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Model") {
            return url
        }
        if let url = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil)?.first(where: { $0.lastPathComponent.contains("label") }) {
            return url
        }
        // Fallback search
        if let resourcePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                for case let file as String in enumerator {
                    if file.hasSuffix("\(name).txt") || file.contains("label") && file.hasSuffix(".txt") {
                        return URL(fileURLWithPath: (resourcePath as NSString).appendingPathComponent(file))
                    }
                }
            }
        }
        return nil
    }

    private func loadLabels(labelsPath: String) {
        if !labelsPath.isEmpty,
           let content = try? String(contentsOfFile: labelsPath, encoding: .utf8) {
            self.labels = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            print("✅ [TFLiteClassifierService] Loaded \(self.labels.count) labels from \(labelsPath)")
        } else {
            // Default labels from model/labels.txt
            self.labels = [
                "0_clear_face",
                "1_clear_eye_with_glass",
                "2_hair_over_face",
                "3_hand_over_face",
                "4_has_hat",
                "5_has_mask",
                "6_has_sunglasses"
            ]
            print("ℹ️ [TFLiteClassifierService] Using default fallback labels list.")
        }
    }

    private func setupInterpreter(modelPath: String) {
        do {
            var options = Interpreter.Options()
            options.threadCount = 2
            self.interpreter = try Interpreter(modelPath: modelPath, options: options)
            try self.interpreter?.allocateTensors()

            if let interpreter = self.interpreter {
                let inputTensor = try interpreter.input(at: 0)
                let dims = inputTensor.shape.dimensions
                if dims.count >= 4 {
                    self.inputHeight = dims[1]
                    self.inputWidth = dims[2]
                    self.inputChannels = dims[3]
                }
                print("✅ [TFLiteClassifierService] Initialized interpreter from \(modelPath)")
                print("   Input Tensor: shape=\(dims), dataType=\(inputTensor.dataType)")
            }
        } catch {
            print("❌ [TFLiteClassifierService] Failed to initialize TFLite interpreter: \(error)")
        }
    }

    public func classify(faceImage: UIImage) async throws -> FaceClassificationOutput {
        guard let interpreter = interpreter else {
            throw NSError(domain: "TFLiteClassifier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Interpreter not initialized"])
        }

        let targetSize = CGSize(width: inputWidth, height: inputHeight)
        guard let resized = TransformUtils.resizeImage(faceImage, targetSize: targetSize) else {
            throw NSError(domain: "TFLiteClassifier", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to resize image to \(inputWidth)x\(inputHeight)"])
        }

        let inputTensor = try interpreter.input(at: 0)
        let inputDataType = inputTensor.dataType
        let inputQuant = inputTensor.quantizationParameters

        guard let inputData = preprocessImage(resized, dataType: inputDataType, quantParams: inputQuant) else {
            throw NSError(domain: "TFLiteClassifier", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create input tensor buffer"])
        }

        // Copy input to tensor at index 0
        try interpreter.copy(inputData, toInputAt: 0)

        // Invoke inference
        let startTime = CFAbsoluteTimeGetCurrent()
        try interpreter.invoke()
        let inferenceTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        // Read output tensor at index 0
        let outputTensor = try interpreter.output(at: 0)
        let outputDataType = outputTensor.dataType
        let outputQuant = outputTensor.quantizationParameters

        let scores: [Float]
        switch outputDataType {
        case .uInt8:
            let scale = outputQuant?.scale ?? 1.0
            let zeroPoint = outputQuant?.zeroPoint ?? 0
            let bytes = [UInt8](outputTensor.data)
            scores = bytes.map { byte in
                Float(Int(byte) - zeroPoint) * scale
            }

        case .float32:
            scores = outputTensor.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        default:
            throw NSError(domain: "TFLiteClassifier", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unsupported tensor type: \(outputDataType)"])
        }

        let maxIndex = scores.indices.max(by: { scores[$0] < scores[$1] }) ?? 0
        let label = labels.indices.contains(maxIndex) ? labels[maxIndex] : "Unknown"
        let confidence = scores.indices.contains(maxIndex) ? scores[maxIndex] : 0.0

        // Diagnostic log matching Android
        debugLog(scores: scores, inferenceTimeMs: inferenceTimeMs, topIndex: maxIndex, topLabel: label, confidence: confidence)

        return FaceClassificationOutput(
            topIndex: maxIndex,
            topLabel: label,
            confidence: confidence,
            scores: scores
        )
    }

    private func preprocessImage(_ image: UIImage, dataType: Tensor.DataType, quantParams: QuantizationParameters?) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        // Use exact model input dimensions (224x224) to prevent Retina scale expansion (e.g. 672x672)
        let width = inputWidth
        let height = inputHeight

        var rawBytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &rawBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        switch dataType {
        case .uInt8:
            var rgbBytes = [UInt8]()
            rgbBytes.reserveCapacity(width * height * 3)
            for i in 0..<(width * height) {
                rgbBytes.append(rawBytes[i * 4 + 0]) // R
                rgbBytes.append(rawBytes[i * 4 + 1]) // G
                rgbBytes.append(rawBytes[i * 4 + 2]) // B
            }
            return Data(rgbBytes)

        case .float32:
            var floatBytes = [Float32]()
            floatBytes.reserveCapacity(width * height * 3)
            let scale = quantParams?.scale ?? 0.0
            let zeroPoint = quantParams?.zeroPoint ?? 0

            for i in 0..<(width * height) {
                let r = Float(rawBytes[i * 4 + 0])
                let g = Float(rawBytes[i * 4 + 1])
                let b = Float(rawBytes[i * 4 + 2])

                if scale > 0 {
                    floatBytes.append((r - Float(zeroPoint)) * scale)
                    floatBytes.append((g - Float(zeroPoint)) * scale)
                    floatBytes.append((b - Float(zeroPoint)) * scale)
                } else {
                    // Standard [0, 1] normalization
                    floatBytes.append(r / 255.0)
                    floatBytes.append(g / 255.0)
                    floatBytes.append(b / 255.0)
                }
            }
            return floatBytes.withUnsafeBufferPointer { Data(buffer: $0) }

        default:
            return nil
        }
    }

    private func debugLog(scores: [Float], inferenceTimeMs: Double, topIndex: Int, topLabel: String, confidence: Float) {
        print("🔍 [TFLiteInference] Inference time: \(String(format: "%.2f", inferenceTimeMs)) ms")
        for (idx, score) in scores.enumerated() {
            let label = labels.indices.contains(idx) ? labels[idx] : "Unknown"
            print("   [\(idx)] \(label) = \(String(format: "%.4f", score))")
        }
        print("✅ [TFLiteInference] Top Prediction: [\(topIndex)] \(topLabel) (\(String(format: "%.2f", confidence * 100))%)")
    }
}
#endif
