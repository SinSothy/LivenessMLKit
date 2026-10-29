//
//  FaceResult.swift
//  LivenessMlKit
//

import Foundation

public struct FaceResult: Equatable {
    public var detected: Bool
    public var canCapture: Bool
    public var message: String

    public init(
        detected: Bool = false,
        canCapture: Bool = false,
        message: String = ""
    ) {
        self.detected = detected
        self.canCapture = canCapture
        self.message = message
    }
}
