//
//  ScreenScanFaceMLView.swift
//  LivenessMlKit
//

import SwiftUI
import AVFoundation

struct ScreenScanFaceMLView: View {
    @StateObject private var viewModel = ScanFaceLivenessVM()
    @StateObject private var cameraManager = CameraManager()
    @State private var analyzer: FaceDetectionAnalyzer?

    var onBackPress: () -> Void = {}

    init(onBackPress: @escaping () -> Void = {}) {
        self.onBackPress = onBackPress
    }

    public var body: some View {
        ZStack {
            // 1. Camera Preview
            if cameraManager.isCameraAuthorized {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Camera permission required")
                        .foregroundColor(.white)
                        .font(.headline)
                    Button("Grant Permission") {
                        cameraManager.checkPermission()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            // 2. Morphing Oval Scanner Clip
            GeometryReader { geo in
                let ovalWidth = geo.size.width * 0.8
                let ovalHeight = geo.size.width * 0.95
                let offsetY = geo.size.height * 0.15
                let boundBox = viewModel.faceResult?.boundingBox ?? .zero

                CmcbCameraClipOvalView(
                    frameWidth: ovalWidth,
                    frameHeight: ovalHeight,
                    offsetY: offsetY,
                    isFaceDetected: viewModel.isFaceDetected,
                    isValid: viewModel.faceResult?.isValid ?? false,
                    boundingBox: boundBox
                )
            }
            .ignoresSafeArea()

            // 3. Top Bar Navigation
            VStack {
                HStack {
                    Button(action: onBackPress) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding()
                    }
                    Spacer()
                    Text("Take Face Photo")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    // Balance header
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.top, 40)
                Spacer()
            }

            // 4. Bottom Controls & Feedback State
            VStack {
                Spacer()

                // Warning / Feedback Icons
                feedbackIcons

                Spacer().frame(height: 16)

                // Status Message Box
                if let state = viewModel.faceResult {
                    statusMessage(for: state)
                        .transition(.opacity.combined(with: .scale))
                } else if let analyze = viewModel.faceLivenessAnalyze {
                    VStack(spacing: 4) {
                        Text(analyze.message)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text("Label: \(analyze.topLabel) | Score: \(String(format: "%.2f", analyze.confidence)) (\(Int(analyze.confidence * 100))%)")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(18)
                }

                Spacer().frame(height: 30)

                // Optional Action Buttons (Flip Camera)
                HStack(spacing: 40) {
                    Button(action: {
                        cameraManager.switchCamera(analyzer: analyzer)
                    }) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            let analyzerInstance = FaceDetectionAnalyzer(callback: viewModel)
            analyzerInstance.cameraPosition = .front
            self.analyzer = analyzerInstance
            cameraManager.setAnalyzer(analyzerInstance)
            cameraManager.checkPermission(analyzer: analyzerInstance)
        }
        .onDisappear {
            cameraManager.stop()
            viewModel.resetState()
        }
    }

    // MARK: - Feedback Icons
    @ViewBuilder
    private var feedbackIcons: some View {
        if let state = viewModel.faceResult, case .inValid(let actionType, _, _) = state {
            HStack(spacing: 20) {
                if actionType == FaceValidationResult.FACE_HAS_MASK {
                    iconBadge(systemName: "facemask.fill", label: "No Mask")
                }
                if actionType == FaceValidationResult.FACE_HAS_SUNGLASSES {
                    iconBadge(systemName: "eyeglasses", label: "No Sunglasses")
                }
                if actionType == FaceValidationResult.FACE_HAS_HAT {
                    iconBadge(systemName: "hat.widebrim.fill", label: "No Hat")
                }
                if actionType == FaceValidationResult.FACE_ORIENTATION {
                    iconBadge(systemName: "person.crop.circle.badge.exclamationmark", label: "Face Straight")
                }
                if actionType == FaceValidationResult.FACE_UNKNOWN {
                    iconBadge(systemName: "person.fill.questionmark", label: "Unknown")
                }
            }
        }
    }

    private func iconBadge(systemName: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 26))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }

    // MARK: - Status Message
    @ViewBuilder
    private func statusMessage(for state: FaceValidationResult) -> some View {
        VStack(spacing: 6) {
            switch state {
            case .valid(_, let analyze):
                Text(analyze?.message ?? "Ready")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0x13 / 255.0, green: 0x9D / 255.0, blue: 0x61 / 255.0))
                    .multilineTextAlignment(.center)

                if let analyze = analyze {
                    Text("Label: \(analyze.topLabel) | Score: \(String(format: "%.2f", analyze.confidence)) (\(Int(analyze.confidence * 100))%)")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }

            case .inValid(let actionType, let message, _):
                Text("\(message) = \(actionType)")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let analyze = viewModel.faceLivenessAnalyze {
                    Text("Label: \(analyze.topLabel) | Score: \(String(format: "%.2f", analyze.confidence)) (\(Int(analyze.confidence * 100))%)")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(.orange.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.75))
        .cornerRadius(18)
    }
}
