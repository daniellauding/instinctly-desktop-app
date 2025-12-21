import SwiftUI
import AppKit

extension Color {
    /// Initialize Color from hex string
    init?(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var hexInt: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&hexInt) else {
            return nil
        }

        let r, g, b, a: Double

        switch cleanHex.count {
        case 6: // RGB
            r = Double((hexInt >> 16) & 0xFF) / 255.0
            g = Double((hexInt >> 8) & 0xFF) / 255.0
            b = Double(hexInt & 0xFF) / 255.0
            a = 1.0
        case 8: // RGBA
            r = Double((hexInt >> 24) & 0xFF) / 255.0
            g = Double((hexInt >> 16) & 0xFF) / 255.0
            b = Double((hexInt >> 8) & 0xFF) / 255.0
            a = Double(hexInt & 0xFF) / 255.0
        default:
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Convert Color to hex string
    var hexString: String {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return "#000000"
        }

        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Convert Color to hex string with alpha
    var hexStringWithAlpha: String {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return "#000000FF"
        }

        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let a = Int(rgb.alphaComponent * 255)

        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// Get RGB components
    var rgbComponents: (red: Int, green: Int, blue: Int)? {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return nil
        }

        return (
            red: Int(rgb.redComponent * 255),
            green: Int(rgb.greenComponent * 255),
            blue: Int(rgb.blueComponent * 255)
        )
    }

    /// Get HSB components
    var hsbComponents: (hue: Double, saturation: Double, brightness: Double)? {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return nil
        }

        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        return (
            hue: Double(h),
            saturation: Double(s),
            brightness: Double(b)
        )
    }

    /// Create a lighter version of the color
    func lighter(by amount: Double = 0.2) -> Color {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return self
        }

        return Color(
            red: min(Double(rgb.redComponent) + amount, 1.0),
            green: min(Double(rgb.greenComponent) + amount, 1.0),
            blue: min(Double(rgb.blueComponent) + amount, 1.0)
        )
    }

    /// Create a darker version of the color
    func darker(by amount: Double = 0.2) -> Color {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return self
        }

        return Color(
            red: max(Double(rgb.redComponent) - amount, 0.0),
            green: max(Double(rgb.greenComponent) - amount, 0.0),
            blue: max(Double(rgb.blueComponent) - amount, 0.0)
        )
    }

    /// Check if color is light or dark
    var isLight: Bool {
        let nsColor = NSColor(self)

        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return false
        }

        // Calculate luminance
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent

        return luminance > 0.5
    }

    /// Get contrasting color (black or white)
    var contrastingColor: Color {
        isLight ? .black : .white
    }
}

// MARK: - Common Colors
extension Color {
    static let annotationRed = Color(hex: "#FF3B30")!
    static let annotationOrange = Color(hex: "#FF9500")!
    static let annotationYellow = Color(hex: "#FFCC00")!
    static let annotationGreen = Color(hex: "#34C759")!
    static let annotationBlue = Color(hex: "#007AFF")!
    static let annotationPurple = Color(hex: "#AF52DE")!
    static let annotationPink = Color(hex: "#FF2D55")!
}
