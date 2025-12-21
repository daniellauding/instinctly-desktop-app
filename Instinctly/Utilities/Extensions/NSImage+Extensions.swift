import AppKit
import CoreGraphics

extension NSImage {
    /// Create a thumbnail of the image
    func thumbnail(maxSize: CGFloat) -> NSImage? {
        let aspectRatio = size.width / size.height
        var thumbnailSize: NSSize

        if size.width > size.height {
            thumbnailSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            thumbnailSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        draw(in: NSRect(origin: .zero, size: thumbnailSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        thumbnail.unlockFocus()

        return thumbnail
    }

    /// Get PNG data representation
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Get JPEG data representation
    func jpegData(compressionQuality: CGFloat = 0.9) -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    /// Resize image to fit within max dimensions while maintaining aspect ratio
    func resized(maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage {
        let aspectRatio = size.width / size.height

        var newSize: NSSize
        if size.width / maxWidth > size.height / maxHeight {
            newSize = NSSize(width: maxWidth, height: maxWidth / aspectRatio)
        } else {
            newSize = NSSize(width: maxHeight * aspectRatio, height: maxHeight)
        }

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        resizedImage.unlockFocus()

        return resizedImage
    }

    /// Crop image to a specific rect
    func cropped(to rect: CGRect) -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Scale rect for actual pixel dimensions
        let scale = CGFloat(cgImage.width) / size.width
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: (size.height - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let croppedCGImage = cgImage.cropping(to: scaledRect) else {
            return nil
        }

        return NSImage(cgImage: croppedCGImage, size: rect.size)
    }

    /// Rotate image by degrees
    func rotated(by degrees: CGFloat) -> NSImage {
        let radians = degrees * .pi / 180

        var newSize = size
        if degrees.truncatingRemainder(dividingBy: 180) != 0 {
            newSize = NSSize(width: size.height, height: size.width)
        }

        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byRadians: radians)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)

        rotatedImage.unlockFocus()
        return rotatedImage
    }

    /// Flip image horizontally
    func flippedHorizontally() -> NSImage {
        let flippedImage = NSImage(size: size)
        flippedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()

        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)

        flippedImage.unlockFocus()
        return flippedImage
    }

    /// Flip image vertically
    func flippedVertically() -> NSImage {
        let flippedImage = NSImage(size: size)
        flippedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: size.height)
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()

        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)

        flippedImage.unlockFocus()
        return flippedImage
    }

    /// Convert to CGImage
    var toCGImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Get pixel color at point
    func color(at point: NSPoint) -> NSColor? {
        guard let cgImage = toCGImage else { return nil }

        let scale = CGFloat(cgImage.width) / size.width
        let scaledPoint = CGPoint(x: point.x * scale, y: point.y * scale)

        guard scaledPoint.x >= 0,
              scaledPoint.y >= 0,
              Int(scaledPoint.x) < cgImage.width,
              Int(scaledPoint.y) < cgImage.height else {
            return nil
        }

        let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { pixelData.deallocate() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.draw(
            cgImage,
            in: CGRect(
                x: -scaledPoint.x,
                y: scaledPoint.y - CGFloat(cgImage.height) + 1,
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        )

        return NSColor(
            red: CGFloat(pixelData[0]) / 255.0,
            green: CGFloat(pixelData[1]) / 255.0,
            blue: CGFloat(pixelData[2]) / 255.0,
            alpha: CGFloat(pixelData[3]) / 255.0
        )
    }
}
