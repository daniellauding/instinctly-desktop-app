import AppKit
import CoreImage
import CoreGraphics
import SwiftUI
import os.log

private let imageLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "ImageProcessing")

/// Service for image processing operations
class ImageProcessingService {

    // MARK: - Crop

    /// Crop an image to a specified rect (in image's logical coordinate space, origin at top-left)
    /// - Parameters:
    ///   - image: Source image
    ///   - rect: Crop rectangle in points (not pixels), with origin at top-left
    /// - Returns: Cropped image or nil if failed
    static func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        imageLogger.info("✂️ cropImage called with rect: \(rect.debugDescription)")
        imageLogger.info("📐 Source image size: \(image.size.width)x\(image.size.height)")

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageLogger.error("❌ Failed to get CGImage from NSImage")
            return nil
        }

        imageLogger.info("🖼️ CGImage size: \(cgImage.width)x\(cgImage.height)")

        // Calculate scale factor between CGImage (pixels) and NSImage (points)
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height

        imageLogger.info("📏 Scale factors: x=\(scaleX), y=\(scaleY)")

        // Input rect is in points with origin at top-left
        // CGImage has origin at top-left, so we just need to scale
        let scaledRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,  // No flip needed - both have top-left origin
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        imageLogger.info("📐 Scaled rect for cropping: \(scaledRect.debugDescription)")

        // Validate rect is within bounds
        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clampedRect = scaledRect.intersection(imageRect)

        if clampedRect.isEmpty || clampedRect.width < 1 || clampedRect.height < 1 {
            imageLogger.error("❌ Invalid crop rect - outside image bounds or too small")
            imageLogger.error("   Image bounds: \(imageRect.debugDescription)")
            imageLogger.error("   Requested: \(scaledRect.debugDescription)")
            imageLogger.error("   Clamped: \(clampedRect.debugDescription)")
            return nil
        }

        imageLogger.info("✅ Clamped rect: \(clampedRect.debugDescription)")

        guard let croppedCGImage = cgImage.cropping(to: clampedRect) else {
            imageLogger.error("❌ CGImage.cropping returned nil")
            return nil
        }

        // Return with correct point size
        let resultSize = NSSize(
            width: clampedRect.width / scaleX,
            height: clampedRect.height / scaleY
        )

        imageLogger.info("✅ Crop successful. Result size: \(resultSize.width)x\(resultSize.height)")

        return NSImage(cgImage: croppedCGImage, size: resultSize)
    }

    // MARK: - Blur

    /// Apply blur to a region of an image
    static func applyBlur(to image: NSImage, in rect: CGRect, radius: CGFloat = 10) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Create blur filter
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        // Scale rect
        let scale = CGFloat(cgImage.width) / image.size.width
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: (CGFloat(cgImage.height) - rect.origin.y * scale - rect.height * scale),
            width: rect.width * scale,
            height: rect.height * scale
        )

        // Crop the region to blur
        let croppedImage = ciImage.cropped(to: scaledRect)

        blurFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        blurFilter.setValue(radius * scale, forKey: kCIInputRadiusKey)

        guard let blurredRegion = blurFilter.outputImage else {
            return nil
        }

        // Composite blurred region back onto original
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return nil
        }

        compositeFilter.setValue(blurredRegion, forKey: kCIInputImageKey)
        compositeFilter.setValue(ciImage, forKey: kCIInputBackgroundImageKey)

        guard let outputImage = compositeFilter.outputImage else {
            return nil
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    /// Apply pixelate effect to a region
    static func applyPixelate(to image: NSImage, in rect: CGRect, scale: CGFloat = 20) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        guard let pixelateFilter = CIFilter(name: "CIPixellate") else {
            return nil
        }

        let imageScale = CGFloat(cgImage.width) / image.size.width
        let scaledRect = CGRect(
            x: rect.origin.x * imageScale,
            y: (CGFloat(cgImage.height) - rect.origin.y * imageScale - rect.height * imageScale),
            width: rect.width * imageScale,
            height: rect.height * imageScale
        )

        let croppedImage = ciImage.cropped(to: scaledRect)

        pixelateFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        pixelateFilter.setValue(scale * imageScale, forKey: kCIInputScaleKey)
        pixelateFilter.setValue(CIVector(cgPoint: CGPoint(x: scaledRect.midX, y: scaledRect.midY)), forKey: kCIInputCenterKey)

        guard let pixelatedRegion = pixelateFilter.outputImage else {
            return nil
        }

        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return nil
        }

        compositeFilter.setValue(pixelatedRegion, forKey: kCIInputImageKey)
        compositeFilter.setValue(ciImage, forKey: kCIInputBackgroundImageKey)

        guard let outputImage = compositeFilter.outputImage else {
            return nil
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    // MARK: - Render Annotations

    /// Render all annotations onto an image
    static func renderAnnotations(on image: NSImage, annotations: [Annotation]) -> NSImage {
        let size = image.size
        imageLogger.info("🎨 Rendering \(annotations.count) annotations on image of size \(size.width)x\(size.height)")

        let resultImage = NSImage(size: size)
        resultImage.lockFocus()

        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: size))

        // Draw each annotation (with coordinate flip for SwiftUI -> NSImage)
        for annotation in annotations {
            imageLogger.debug("🎨 Rendering annotation type: \(annotation.type.rawValue)")
            renderAnnotation(annotation, imageHeight: size.height)
        }

        resultImage.unlockFocus()
        imageLogger.info("✅ Finished rendering annotations")
        return resultImage
    }

    /// Flip Y coordinate from SwiftUI (top-left origin) to NSImage (bottom-left origin)
    private static func flipY(_ y: CGFloat, imageHeight: CGFloat) -> CGFloat {
        return imageHeight - y
    }

    /// Flip a point's Y coordinate
    private static func flipPoint(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        return CGPoint(x: point.x, y: imageHeight - point.y)
    }

    /// Flip a rect's Y coordinate (origin is at bottom-left after flip)
    private static func flipRect(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        return CGRect(
            x: rect.origin.x,
            y: imageHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func renderAnnotation(_ annotation: Annotation, imageHeight: CGFloat) {
        let context = NSGraphicsContext.current!.cgContext

        switch annotation.type {
        case .arrow:
            renderArrow(annotation, in: context, imageHeight: imageHeight)

        case .line:
            renderLine(annotation, in: context, imageHeight: imageHeight)

        case .rectangle:
            renderRectangle(annotation, in: context, imageHeight: imageHeight)

        case .circle:
            renderCircle(annotation, in: context, imageHeight: imageHeight)

        case .freehand, .highlighter:
            renderFreehand(annotation, in: context, imageHeight: imageHeight)

        case .text:
            renderText(annotation, imageHeight: imageHeight)

        case .blur:
            // Blur would need to be applied to the base image before rendering
            break

        case .numberedStep:
            renderNumberedStep(annotation, in: context, imageHeight: imageHeight)

        case .callout:
            renderCallout(annotation, imageHeight: imageHeight)

        case .crop:
            // Crop is handled separately
            break
        }
    }

    private static func renderArrow(_ annotation: Annotation, in context: CGContext, imageHeight: CGFloat) {
        guard let start = annotation.startPoint, let end = annotation.endPoint else { return }

        // Flip Y coordinates for NSImage coordinate system
        let flippedStart = flipPoint(start, imageHeight: imageHeight)
        let flippedEnd = flipPoint(end, imageHeight: imageHeight)

        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw line
        context.move(to: flippedStart)
        context.addLine(to: flippedEnd)
        context.strokePath()

        // Draw arrowhead
        let angle = atan2(flippedEnd.y - flippedStart.y, flippedEnd.x - flippedStart.x)
        let arrowLength: CGFloat = 15 + annotation.strokeWidth
        let arrowAngle: CGFloat = .pi / 6

        context.move(to: flippedEnd)
        context.addLine(to: CGPoint(
            x: flippedEnd.x - arrowLength * cos(angle - arrowAngle),
            y: flippedEnd.y - arrowLength * sin(angle - arrowAngle)
        ))
        context.move(to: flippedEnd)
        context.addLine(to: CGPoint(
            x: flippedEnd.x - arrowLength * cos(angle + arrowAngle),
            y: flippedEnd.y - arrowLength * sin(angle + arrowAngle)
        ))
        context.strokePath()
    }

    private static func renderLine(_ annotation: Annotation, in context: CGContext, imageHeight: CGFloat) {
        guard let start = annotation.startPoint, let end = annotation.endPoint else { return }

        // Flip Y coordinates
        let flippedStart = flipPoint(start, imageHeight: imageHeight)
        let flippedEnd = flipPoint(end, imageHeight: imageHeight)

        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)

        context.move(to: flippedStart)
        context.addLine(to: flippedEnd)
        context.strokePath()
    }

    private static func renderRectangle(_ annotation: Annotation, in context: CGContext, imageHeight: CGFloat) {
        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)

        // Flip Y coordinate for rect
        let flippedRect = flipRect(annotation.frame, imageHeight: imageHeight)
        context.stroke(flippedRect)
    }

    private static func renderCircle(_ annotation: Annotation, in context: CGContext, imageHeight: CGFloat) {
        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)

        // Flip Y coordinate for rect
        let flippedRect = flipRect(annotation.frame, imageHeight: imageHeight)
        context.strokeEllipse(in: flippedRect)
    }

    private static func renderFreehand(_ annotation: Annotation, in context: CGContext, imageHeight: CGFloat) {
        guard annotation.points.count > 1 else { return }

        let nsColor = NSColor(annotation.color)

        if annotation.type == .highlighter {
            context.setStrokeColor(nsColor.withAlphaComponent(0.4).cgColor)
            context.setBlendMode(.multiply)
        } else {
            context.setStrokeColor(nsColor.cgColor)
        }

        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Flip Y coordinates for all points
        let flippedFirst = flipPoint(annotation.points[0], imageHeight: imageHeight)
        context.move(to: flippedFirst)
        for point in annotation.points.dropFirst() {
            let flippedPoint = flipPoint(point, imageHeight: imageHeight)
            context.addLine(to: flippedPoint)
        }
        context.strokePath()

        if annotation.type == .highlighter {
            context.setBlendMode(.normal)
        }
    }

    private static func renderText(_ annotation: Annotation, imageHeight: CGFloat) {
        guard let text = annotation.text else { return }

        let font = NSFont.systemFont(ofSize: annotation.fontSize ?? 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(annotation.color)
        ]

        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()

        // Flip Y coordinate for text position (text draws from bottom-left of baseline)
        let flippedPoint = CGPoint(
            x: annotation.frame.origin.x,
            y: imageHeight - annotation.frame.origin.y - textSize.height
        )
        string.draw(at: flippedPoint)
    }

    private static func renderNumberedStep(_ annotation: Annotation, in context: CGContext, imageHeight: CGFloat) {
        let nsColor = NSColor(annotation.color)

        // Flip Y coordinate for circle
        let flippedRect = flipRect(
            CGRect(
                x: annotation.frame.origin.x,
                y: annotation.frame.origin.y,
                width: 30,
                height: 30
            ),
            imageHeight: imageHeight
        )

        // Draw circle
        context.setFillColor(nsColor.cgColor)
        context.fillEllipse(in: flippedRect)

        // Draw number
        let number = "\(annotation.stepNumber ?? 1)"
        let font = NSFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let string = NSAttributedString(string: number, attributes: attributes)
        let textSize = string.size()
        let textPoint = CGPoint(
            x: flippedRect.midX - textSize.width / 2,
            y: flippedRect.midY - textSize.height / 2
        )
        string.draw(at: textPoint)
    }

    private static func renderCallout(_ annotation: Annotation, imageHeight: CGFloat) {
        let nsColor = NSColor(annotation.color)

        // Flip Y coordinate for bubble
        let flippedRect = flipRect(annotation.frame, imageHeight: imageHeight)

        // Draw bubble
        let path = NSBezierPath(roundedRect: flippedRect, xRadius: 8, yRadius: 8)
        nsColor.withAlphaComponent(0.9).setFill()
        path.fill()

        // Draw text
        if let text = annotation.text {
            let font = NSFont.systemFont(ofSize: annotation.fontSize ?? 14)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]

            let string = NSAttributedString(string: text, attributes: attributes)
            let textRect = flippedRect.insetBy(dx: 8, dy: 8)
            string.draw(in: textRect)
        }
    }

    // MARK: - Export

    /// Export image as PNG data
    static func exportAsPNG(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Export image as JPEG data
    static func exportAsJPEG(_ image: NSImage, quality: CGFloat = 0.9) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Export image as PDF data
    static func exportAsPDF(_ image: NSImage) -> Data? {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            return nil
        }

        var mediaBox = CGRect(origin: .zero, size: image.size)

        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        context.beginPage(mediaBox: &mediaBox)

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: mediaBox)
        }

        context.endPage()
        context.closePDF()

        return pdfData as Data
    }
}
