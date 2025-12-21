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

        let resultImage = NSImage(size: size)
        resultImage.lockFocus()

        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: size))

        // Draw each annotation
        for annotation in annotations {
            renderAnnotation(annotation, scale: 1.0)
        }

        resultImage.unlockFocus()
        return resultImage
    }

    private static func renderAnnotation(_ annotation: Annotation, scale: CGFloat) {
        let context = NSGraphicsContext.current!.cgContext

        switch annotation.type {
        case .arrow:
            renderArrow(annotation, in: context)

        case .line:
            renderLine(annotation, in: context)

        case .rectangle:
            renderRectangle(annotation, in: context)

        case .circle:
            renderCircle(annotation, in: context)

        case .freehand, .highlighter:
            renderFreehand(annotation, in: context)

        case .text:
            renderText(annotation)

        case .blur:
            // Blur would need to be applied to the base image before rendering
            break

        case .numberedStep:
            renderNumberedStep(annotation, in: context)

        case .callout:
            renderCallout(annotation)

        case .crop:
            // Crop is handled separately
            break
        }
    }

    private static func renderArrow(_ annotation: Annotation, in context: CGContext) {
        guard let start = annotation.startPoint, let end = annotation.endPoint else { return }

        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6

        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        ))
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        ))
        context.strokePath()
    }

    private static func renderLine(_ annotation: Annotation, in context: CGContext) {
        guard let start = annotation.startPoint, let end = annotation.endPoint else { return }

        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private static func renderRectangle(_ annotation: Annotation, in context: CGContext) {
        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)

        context.stroke(annotation.frame)
    }

    private static func renderCircle(_ annotation: Annotation, in context: CGContext) {
        let nsColor = NSColor(annotation.color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(annotation.strokeWidth)

        context.strokeEllipse(in: annotation.frame)
    }

    private static func renderFreehand(_ annotation: Annotation, in context: CGContext) {
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

        context.move(to: annotation.points[0])
        for point in annotation.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        if annotation.type == .highlighter {
            context.setBlendMode(.normal)
        }
    }

    private static func renderText(_ annotation: Annotation) {
        guard let text = annotation.text else { return }

        let font = NSFont.systemFont(ofSize: annotation.fontSize ?? 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(annotation.color)
        ]

        let string = NSAttributedString(string: text, attributes: attributes)
        string.draw(at: annotation.frame.origin)
    }

    private static func renderNumberedStep(_ annotation: Annotation, in context: CGContext) {
        let nsColor = NSColor(annotation.color)

        // Draw circle
        context.setFillColor(nsColor.cgColor)
        let circleRect = CGRect(
            x: annotation.frame.origin.x,
            y: annotation.frame.origin.y,
            width: 30,
            height: 30
        )
        context.fillEllipse(in: circleRect)

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
            x: circleRect.midX - textSize.width / 2,
            y: circleRect.midY - textSize.height / 2
        )
        string.draw(at: textPoint)
    }

    private static func renderCallout(_ annotation: Annotation) {
        let nsColor = NSColor(annotation.color)

        // Draw bubble
        let path = NSBezierPath(roundedRect: annotation.frame, xRadius: 8, yRadius: 8)
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
            let textRect = annotation.frame.insetBy(dx: 8, dy: 8)
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
