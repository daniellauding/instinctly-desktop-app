import AppKit
import CoreGraphics

/// Extracts color information from images
class ColorExtractor {

    /// Get color from an NSImage at a specific point
    static func getColor(from image: NSImage, at point: CGPoint) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Account for image scale
        let scale = CGFloat(cgImage.width) / image.size.width
        let scaledPoint = CGPoint(x: point.x * scale, y: point.y * scale)

        // Ensure point is within bounds
        guard scaledPoint.x >= 0,
              scaledPoint.y >= 0,
              Int(scaledPoint.x) < cgImage.width,
              Int(scaledPoint.y) < cgImage.height else {
            return nil
        }

        // Create a 1x1 pixel bitmap context
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

        // Draw the single pixel
        context.draw(
            cgImage,
            in: CGRect(
                x: -scaledPoint.x,
                y: scaledPoint.y - CGFloat(cgImage.height) + 1,
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        )

        // Extract color components
        let red = CGFloat(pixelData[0]) / 255.0
        let green = CGFloat(pixelData[1]) / 255.0
        let blue = CGFloat(pixelData[2]) / 255.0
        let alpha = CGFloat(pixelData[3]) / 255.0

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Get average color from a region of an image
    static func getAverageColor(from image: NSImage, in rect: CGRect) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scale = CGFloat(cgImage.width) / image.size.width
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: (image.size.height - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let croppedImage = cgImage.cropping(to: scaledRect) else {
            return nil
        }

        let width = croppedImage.width
        let height = croppedImage.height
        let totalPixels = width * height

        guard totalPixels > 0 else { return nil }

        let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: totalPixels * 4)
        defer { pixelData.deallocate() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalRed: UInt64 = 0
        var totalGreen: UInt64 = 0
        var totalBlue: UInt64 = 0
        var totalAlpha: UInt64 = 0

        for i in 0..<totalPixels {
            let offset = i * 4
            totalRed += UInt64(pixelData[offset])
            totalGreen += UInt64(pixelData[offset + 1])
            totalBlue += UInt64(pixelData[offset + 2])
            totalAlpha += UInt64(pixelData[offset + 3])
        }

        let avgRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
        let avgGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
        let avgBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
        let avgAlpha = CGFloat(totalAlpha) / CGFloat(totalPixels) / 255.0

        return NSColor(red: avgRed, green: avgGreen, blue: avgBlue, alpha: avgAlpha)
    }

    /// Convert NSColor to hex string
    static func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return "#000000"
        }

        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Convert hex string to NSColor
    static func color(from hex: String) -> NSColor? {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        guard cleanHex.count == 6,
              let hexInt = UInt64(cleanHex, radix: 16) else {
            return nil
        }

        let r = CGFloat((hexInt >> 16) & 0xFF) / 255.0
        let g = CGFloat((hexInt >> 8) & 0xFF) / 255.0
        let b = CGFloat(hexInt & 0xFF) / 255.0

        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Get RGB components as tuple
    static func rgbComponents(from color: NSColor) -> (r: Int, g: Int, b: Int)? {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return nil
        }

        return (
            r: Int(rgb.redComponent * 255),
            g: Int(rgb.greenComponent * 255),
            b: Int(rgb.blueComponent * 255)
        )
    }
}
