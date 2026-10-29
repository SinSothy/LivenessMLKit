//
//  FaceValidationResult.swift
//  LivenessMlKit
//

import Foundation
import CoreGraphics

public enum FaceValidationResult: Equatable {
    // Action / Error Type Constants matching Android implementation
    public static let FACE_VALID: Int = 0
    public static let FACE_HAIR_OVER: Int = 2
    public static let FACE_HAND_OVER: Int = 3
    public static let FACE_HAS_HAT: Int = 4
    public static let FACE_HAS_MASK: Int = 5
    public static let FACE_HAS_SUNGLASSES: Int = 6

    public static let FACE_UNKNOWN: Int = 100
    public static let FACE_FAILED: Int = 101
    public static let FACE_NOT_FULL_FRAME: Int = 102
    public static let FACE_FAR_FROM_FRAME: Int = 103
    public static let FACE_BRIGHTNESS_BRIGHT: Int = 104
    public static let FACE_BRIGHTNESS_DARK: Int = 105
    public static let FACE_EYE_CLOSE: Int = 106
    public static let FACE_ORIENTATION: Int = 107
    public static let FACE_NO_LIVENESS: Int = 108

    case valid(
        boundingBox: CGRect?,
        faceLivenessAnalyze: FaceLivenessAnalyze?
    )
    case inValid(
        actionType: Int,
        message: String,
        boundingBox: CGRect?
    )

    public var boundingBox: CGRect? {
        switch self {
        case .valid(let box, _):
            return box
        case .inValid(_, _, let box):
            return box
        }
    }

    public var actionType: Int {
        switch self {
        case .valid:
            return FaceValidationResult.FACE_VALID
        case .inValid(let type, _, _):
            return type
        }
    }

    public var message: String {
        switch self {
        case .valid(_, let analyze):
            return analyze?.message ?? ""
        case .inValid(_, let msg, _):
            return msg
        }
    }

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}
