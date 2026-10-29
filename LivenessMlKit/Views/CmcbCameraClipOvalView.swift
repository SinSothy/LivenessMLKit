//
//  CmcbCameraClipOvalView.swift
//  LivenessMlKit
//

import SwiftUI

public struct CmcbCameraClipOvalView: View {
    public let frameWidth: CGFloat
    public let frameHeight: CGFloat
    public let offsetY: CGFloat
    public let isFaceDetected: Bool
    public let isValid: Bool
    public let boundingBox: CGRect

    public init(
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        offsetY: CGFloat,
        isFaceDetected: Bool = false,
        isValid: Bool = false,
        boundingBox: CGRect = .zero
    ) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.offsetY = offsetY
        self.isFaceDetected = isFaceDetected
        self.isValid = isValid
        self.boundingBox = boundingBox
    }

    public var body: some View {
        GeometryReader { geometry in
            let canvasWidth = geometry.size.width
            let frameLeft = (canvasWidth - frameWidth) / 2.0
            let frameTop = offsetY
            let frameRect = CGRect(x: frameLeft, y: frameTop, width: frameWidth, height: frameHeight)

            MorphingClipCanvas(
                frameRect: frameRect,
                progress: isFaceDetected ? 1.0 : 0.0,
                isFaceDetected: isFaceDetected,
                isValid: isValid,
                boundingBox: boundingBox
            )
            .animation(.easeInOut(duration: 0.45), value: isFaceDetected)
        }
    }
}

// MARK: - Morphing Clip Canvas
private struct MorphingClipCanvas: View, Animatable {
    var frameRect: CGRect
    var progress: Double
    var isFaceDetected: Bool
    var isValid: Bool
    var boundingBox: CGRect

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let morph = CGFloat(max(0.0, min(1.0, progress)))

            // 1. Cutout Mask: Dim background with 75% black, leaving the morphing frame 100% transparent
            let cutoutPath = createMorphPath(rect: frameRect, t: morph)
            var fullScreenMask = Path()
            fullScreenMask.addRect(CGRect(origin: .zero, size: size))
            fullScreenMask.addPath(cutoutPath)
            context.fill(
                fullScreenMask,
                with: .color(Color.black.opacity(0.75)),
                style: FillStyle(eoFill: true)
            )

            // 2. Stroke outline: transitions from white (idle rectangle) to brand green #139D61 (detected oval)
            let strokeColor = Color(
                red: 1.0 + (0x13 / 255.0 - 1.0) * Double(morph),
                green: 1.0 + (0x9D / 255.0 - 1.0) * Double(morph),
                blue: 1.0 + (0x61 / 255.0 - 1.0) * Double(morph)
            )
            context.stroke(cutoutPath, with: .color(strokeColor), lineWidth: 2.5)

            // 3. Scanner Corners: 4 red rounded corner brackets that fade out as the frame morphs to oval
            let redAlpha = max(0.0, min(1.0, 1.0 - morph))
            if redAlpha > 0.001 {
                let cornerColor = Color.red.opacity(Double(redAlpha))
                let cornerPath = createScannerCornersPath(rect: frameRect, t: morph)
                context.stroke(
                    cornerPath,
                    with: .color(cornerColor),
                    style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
                )
            }

            #if DEBUG
            if boundingBox != .zero {
                let debugBox = Path(boundingBox)
                context.stroke(debugBox, with: .color(Color.green.opacity(0.3)), lineWidth: 1.0)
            }
            #endif
        }
    }

    private func createMorphPath(rect: CGRect, t: CGFloat) -> Path {
        let clampedT = max(0.0, min(1.0, t))
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY

        let maxRx = w / 2.0
        let maxRy = h / 2.0
        let minRadius = min(w, h) * 0.12

        // Interpolated corner radii
        let rx = minRadius + (maxRx - minRadius) * clampedT
        let ry = minRadius + (maxRy - minRadius) * clampedT

        // Half-length of the straight segments (shrinks to 0 when morph reaches 1.0)
        let dx = (maxRx - minRadius) * (1.0 - clampedT)
        let dy = (maxRy - minRadius) * (1.0 - clampedT)

        // Cubic Bézier factor for 90-degree elliptical arc
        let kappa: CGFloat = 0.5522847498307936

        var path = Path()

        // Start at top edge right end: (cx + dx, cy - maxRy)
        path.move(to: CGPoint(x: cx + dx, y: cy - maxRy))

        // 1. Top-Right Corner
        path.addCurve(
            to: CGPoint(x: cx + maxRx, y: cy - dy),
            control1: CGPoint(x: cx + dx + rx * kappa, y: cy - maxRy),
            control2: CGPoint(x: cx + maxRx, y: cy - dy - ry * kappa)
        )

        // 2. Right Edge
        if dy > 0 {
            path.addLine(to: CGPoint(x: cx + maxRx, y: cy + dy))
        }

        // 3. Bottom-Right Corner
        path.addCurve(
            to: CGPoint(x: cx + dx, y: cy + maxRy),
            control1: CGPoint(x: cx + maxRx, y: cy + dy + ry * kappa),
            control2: CGPoint(x: cx + dx + rx * kappa, y: cy + maxRy)
        )

        // 4. Bottom Edge
        if dx > 0 {
            path.addLine(to: CGPoint(x: cx - dx, y: cy + maxRy))
        }

        // 5. Bottom-Left Corner
        path.addCurve(
            to: CGPoint(x: cx - maxRx, y: cy + dy),
            control1: CGPoint(x: cx - dx - rx * kappa, y: cy + maxRy),
            control2: CGPoint(x: cx - maxRx, y: cy + dy + ry * kappa)
        )

        // 6. Left Edge
        if dy > 0 {
            path.addLine(to: CGPoint(x: cx - maxRx, y: cy - dy))
        }

        // 7. Top-Left Corner
        path.addCurve(
            to: CGPoint(x: cx - dx, y: cy - maxRy),
            control1: CGPoint(x: cx - maxRx, y: cy - dy - ry * kappa),
            control2: CGPoint(x: cx - dx - rx * kappa, y: cy - maxRy)
        )

        // 8. Close path across top edge
        path.closeSubpath()

        return path
    }

    private func createScannerCornersPath(
        rect: CGRect,
        t: CGFloat,
        cornerLength: CGFloat = 30.0,
        padding: CGFloat = 16.0
    ) -> Path {
        var path = Path()
        let paddedRect = rect.insetBy(dx: -padding, dy: -padding)

        let clampedT = max(0.0, min(1.0, t))
        let minCorner = min(rect.width, rect.height) * 0.12
        let maxCorner = min(paddedRect.width, paddedRect.height) * 0.40
        let cornerRadius = minCorner + (maxCorner - minCorner) * clampedT

        // 1. Top-Left Corner Bracket
        path.move(to: CGPoint(x: paddedRect.minX, y: paddedRect.minY + cornerRadius + cornerLength))
        path.addLine(to: CGPoint(x: paddedRect.minX, y: paddedRect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: paddedRect.minX + cornerRadius, y: paddedRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.minX + cornerRadius + cornerLength, y: paddedRect.minY))

        // 2. Top-Right Corner Bracket
        path.move(to: CGPoint(x: paddedRect.maxX - cornerRadius - cornerLength, y: paddedRect.minY))
        path.addLine(to: CGPoint(x: paddedRect.maxX - cornerRadius, y: paddedRect.minY))
        path.addArc(
            center: CGPoint(x: paddedRect.maxX - cornerRadius, y: paddedRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.maxX, y: paddedRect.minY + cornerRadius + cornerLength))

        // 3. Bottom-Right Corner Bracket
        path.move(to: CGPoint(x: paddedRect.maxX, y: paddedRect.maxY - cornerRadius - cornerLength))
        path.addLine(to: CGPoint(x: paddedRect.maxX, y: paddedRect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: paddedRect.maxX - cornerRadius, y: paddedRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: paddedRect.maxX - cornerRadius - cornerLength, y: paddedRect.maxY))

        // 4. Bottom-Left Corner Bracket
        path.move(to: CGPoint(x: paddedRect.minX + cornerRadius + cornerLength, y: paddedRect.maxY))
        path.addLine(to: CGPoint(x: paddedRect.minX + cornerRadius, y: paddedRect.maxY))
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
