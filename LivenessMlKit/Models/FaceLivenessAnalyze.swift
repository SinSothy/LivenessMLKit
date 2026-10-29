//
//  FaceLivenessAnalyze.swift
//  LivenessMlKit
//

import Foundation

public struct FaceLivenessAnalyze: Equatable {
    public var confidence: Float
    public var topLabel: String
    public var isBlinkDetected: Bool
    public var message: String

    public init(
        confidence: Float,
        topLabel: String,
        isBlinkDetected: Bool,
        message: String
    ) {
        self.confidence = confidence
        self.topLabel = topLabel
        self.isBlinkDetected = isBlinkDetected
        self.message = message
    }
}
