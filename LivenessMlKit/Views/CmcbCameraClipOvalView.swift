//
//  CmcbCameraClipOvalView.swift
//  LivenessMlKit
//

import SwiftUI

public struct CmcbCameraClipOvalView: View {
    public let frameWidth: CGFloat
    public let frameHeight: CGFloat
    public let offsetY: CGFloat
    public let boundingBox: CGRect

    public init(
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        offsetY: CGFloat,
        boundingBox: CGRect
    ) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.offsetY = offsetY
        self.boundingBox = boundingBox
    }

    public var body: some View {
        GeometryReader { geometry in
            let canvasWidth = geometry.size.width
            let canvasHeight = geometry.size.height

            let frameLeft = (canvasWidth - frameWidth) / 2.0
            let frameTop = offsetY
            let frameRect = CGRect(x: frameLeft, y: frameTop, width: frameWidth, height: frameHeight)

            let isInsideTarget = canvasWidth > 0 && canvasHeight > 0 &&
                boundingBox.minX >= frameRect.minX &&
                boundingBox.minY >= frameRect.minY &&
                boundingBox.maxX <= frameRect.maxX &&
                boundingBox.maxY <= frameRect.maxY &&
                boundingBox.width > 0 && boundingBox.height > 0

            MorphingClipCanvas(
                frameRect: frameRect,
                isInsideTarget: isInsideTarget,
                boundingBox: boundingBox
            )
            .animation(.easeInOut(duration: 0.45), value: isInsideTarget)
        }
    }
}

// MARK: - Morphing Clip Canvas
private struct MorphingClipCanvas: View, Animatable {
    var frameRect: CGRect
    var isInsideTarget: Bool
    var boundingBox: CGRect
    var morphProgress: Double

    init(frameRect: CGRect, isInsideTarget: Bool, boundingBox: CGRect) {
        self.frameRect = frameRect
        self.isInsideTarget = isInsideTarget
        self.boundingBox = boundingBox
        self.morphProgress = isInsideTarget ? 1.0 : 0.0
    }

    var animatableData: Double {
        get { morphProgress }
        set { morphProgress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let morph = CGFloat(morphProgress)

            // 1. Dim background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.black.opacity(0.8))
            )

            // 2. Clear cutout (Mask)
            let cutoutPath = createMorphPath(rect: frameRect, t: morph)
            context.blendMode = .clear
            context.fill(cutoutPath, with: .color(.white))

            // 3. Reset blend mode for drawing borders
            context.blendMode = .normal

            // Outline stroke following cutout shape
            let strokeColor = isInsideTarget ? Color(red: 0x13 / 255.0, green: 0x9D / 255.0, blue: 0x61 / 255.0) : Color.white
            context.stroke(cutoutPath, with: .color(strokeColor), lineWidth: 2)

            // 4. Scanner Corners (Red, fades out when face is valid)
            let redAlpha = max(0, min(1.0, 1.0 - morph))
            if redAlpha > 0 {
                let cornerColor = Color.red.opacity(Double(redAlpha))
                let cornerPath = createScannerCornersPath(rect: frameRect, t: morph)
                context.stroke(cornerPath, with: .color(cornerColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            #if DEBUG
            if boundingBox != .zero {
                let debugBox = Path(boundingBox)
                context.stroke(debugBox, with: .color(.green.opacity(0.5)), lineWidth: 1.5)
            }
            #endif
        }
    }

    private func createMorphPath(rect: CGRect, t: CGFloat) -> Path {
        let clampedT = max(0.0, min(1.0, t))
        if clampedT >= 1.0 {
            return Path(ellipseIn: rect)
        }

        let w = rect.width
        let h = rect.height
        let minCorner = min(w, h) * 0.20
        let maxCorner = w / 2.0
        let cornerRadius = minCorner + (maxCorner - minCorner) * clampedT

        return Path(roundedRect: rect, cornerRadius: cornerRadius)
    }

    private func createScannerCornersPath(
        rect: CGRect,
        t: CGFloat,
        cornerLength: CGFloat = 30.0,
        padding: CGFloat = 20.0
    ) -> Path {
        var path = Path()
        let paddedRect = rect.insetBy(dx: -padding, dy: -padding)

        let clampedT = max(0.0, min(1.0, t))
        let w = paddedRect.width
        let h = paddedRect.height
        let minCorner = min(w, h) * 0.20
        let maxCorner = w / 2.0
        let cornerRadius = minCorner + (maxCorner - minCorner) * clampedT

        // Top-Left Corner
        path.addArc(
            center: CGPoint(x: paddedRect.minX + cornerRadius, y: paddedRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.minX + cornerRadius + cornerLength, y: paddedRect.minY))

        // Top-Right Corner
        path.addArc(
            center: CGPoint(x: paddedRect.maxX - cornerRadius, y: paddedRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.maxX, y: paddedRect.minY + cornerRadius + cornerLength))

        // Bottom-Right Corner
        path.addArc(
            center: CGPoint(x: paddedRect.maxX - cornerRadius, y: paddedRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.maxX - cornerRadius - cornerLength, y: paddedRect.maxY))

        // Bottom-Left Corner
        path.addArc(
            center: CGPoint(x: paddedRect.minX + cornerRadius, y: paddedRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.minX, y: paddedRect.maxY - cornerRadius - cornerLength))

        return path
    }
}
