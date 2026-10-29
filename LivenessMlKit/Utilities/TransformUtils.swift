//
//  TransformUtils.swift
//  LivenessMlKit
//

import UIKit
import CoreMedia
import CoreVideo
import Accelerate

public final class TransformUtils {

    /// Estimates the average luminance (brightness) in range 0...255 from CMSampleBuffer / CVPixelBuffer.
    public static func estimateBrightness(from sampleBuffer: CMSampleBuffer) -> Double {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return 128.0
        }
        return estimateBrightness(from: pixelBuffer)
    }

    /// Estimates the average luminance (brightness) in range 0...255 from CVPixelBuffer.
    public static func estimateBrightness(from pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        if isPlanar {
            // Y plane is plane 0 in YUV (BiPlanar 420)
            guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                return 128.0
            }
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

            var totalLuminance: UInt64 = 0
            let step = 4 // sample every 4th pixel for high performance
            var count: UInt64 = 0

            for y in stride(from: 0, to: height, by: step) {
                let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: 0, to: width, by: step) {
                    totalLuminance += UInt64(rowPtr[x])
                    count += 1
                }
            }

            return count > 0 ? Double(totalLuminance) / Double(count) : 128.0
        } else {
            // Packed format (e.g. BGRA)
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return 128.0
            }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            var totalLuminance: Double = 0.0
            let step = 4
            var count: Double = 0.0

            for y in stride(from: 0, to: height, by: step) {
                let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: 0, to: width, by: step) {
                    let b = Double(rowPtr[x * 4 + 0])
                    let g = Double(rowPtr[x * 4 + 1])
                    let r = Double(rowPtr[x * 4 + 2])
                    // Standard Rec. 601 luminance
                    let luma = 0.299 * r + 0.587 * g + 0.114 * b
                    totalLuminance += luma
                    count += 1.0
                }
            }

            return count > 0 ? totalLuminance / count : 128.0
        }
    }

    /// Scales and expands the face bounding box to include hair, forehead, and sides.
    public static func scaleBoundingBox(
        box: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        expandTopRatio: CGFloat = 0.6,
        expandBottomRatio: CGFloat = 0.0,
        expandSideRatio: CGFloat = 0.4
    ) -> CGRect {
        let width = box.width
        let height = box.height

        let left = max(0, box.minX - width * expandSideRatio)
        let right = min(imageWidth, box.maxX + width * expandSideRatio)

        let top = max(0, box.minY - height * expandTopRatio)
        let bottom = min(imageHeight, box.maxY + height * expandBottomRatio)

        return CGRect(
            x: left,
            y: top,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    /// Crops a UIImage to the specified rect.
    public static func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let clampedRect = CGRect(
            x: max(0, rect.origin.x),
            y: max(0, rect.origin.y),
            width: min(CGFloat(cgImage.width) - max(0, rect.origin.x), rect.width),
            height: min(CGFloat(cgImage.height) - max(0, rect.origin.y), rect.height)
        )
        guard clampedRect.width > 0, clampedRect.height > 0,
              let cropped = cgImage.cropping(to: clampedRect) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Zooms into the center of the image by factor (e.g. 1.2f ~ 1.5f).
    public static func zoomImage(_ image: UIImage, factor: CGFloat) -> UIImage? {
        guard factor > 1.0 else { return image }
        let size = image.size
        let cropWidth = size.width / factor
        let cropHeight = size.height / factor
        let cropOriginX = (size.width - cropWidth) / 2.0
        let cropOriginY = (size.height - cropHeight) / 2.0

        let cropRect = CGRect(x: cropOriginX, y: cropOriginY, width: cropWidth, height: cropHeight)
        return cropImage(image, to: cropRect)
    }

    /// Resizes UIImage to a square target size (e.g. 224x224) with 1.0 pixel scale (not device Retina scale).
    public static func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Converts CMSampleBuffer to a properly oriented UIImage.
    public static func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation = .right) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }

    /// Converts normalized or image-space bounding box to View coordinates.
    public static func convert(
        rect: CGRect,
        fromImageSize imageSize: CGSize,
        toViewSize viewSize: CGSize,
        isFrontCamera: Bool = true
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (viewSize.width - scaledWidth) / 2.0
        let offsetY = (viewSize.height - scaledHeight) / 2.0

        var x = rect.origin.x * scale + offsetX
        let y = rect.origin.y * scale + offsetY
        let w = rect.size.width * scale
        let h = rect.size.height * scale

        if isFrontCamera {
            x = viewSize.width - (x + w)
        }

        return CGRect(x: x, y: y, width: w, height: h)
    }
}
