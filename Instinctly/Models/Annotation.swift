import SwiftUI
import Foundation

// MARK: - Annotation Type
enum AnnotationType: String, Codable, CaseIterable {
    case arrow
    case line
    case rectangle
    case circle
    case freehand
    case highlighter
    case text
    case blur
    case numberedStep
    case callout
    case crop
}

// MARK: - Codable Color Wrapper
struct CodableColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ color: Color) {
        let nsColor = NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Annotation Model
struct Annotation: Identifiable, Codable {
    let id: UUID
    var type: AnnotationType
    var frame: CGRect
    var codableColor: CodableColor
    var strokeWidth: CGFloat

    // Shape-specific
    var startPoint: CGPoint?
    var endPoint: CGPoint?

    // Freehand-specific
    var points: [CGPoint]

    // Text-specific
    var text: String?
    var fontSize: CGFloat?
    var fontName: String?

    // Numbered step
    var stepNumber: Int?

    // Callout
    var calloutPointerDirection: CalloutPointerDirection?

    // Computed property for Color
    var color: Color {
        get { codableColor.color }
        set { codableColor = CodableColor(newValue) }
    }

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        frame: CGRect,
        color: Color,
        strokeWidth: CGFloat,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        points: [CGPoint] = [],
        text: String? = nil,
        fontSize: CGFloat? = nil,
        fontName: String? = nil,
        stepNumber: Int? = nil,
        calloutPointerDirection: CalloutPointerDirection? = nil
    ) {
        self.id = id
        self.type = type
        self.frame = frame
        self.codableColor = CodableColor(color)
        self.strokeWidth = strokeWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.text = text
        self.fontSize = fontSize
        self.fontName = fontName
        self.stepNumber = stepNumber
        self.calloutPointerDirection = calloutPointerDirection
    }
}

// MARK: - Callout Pointer Direction
enum CalloutPointerDirection: String, Codable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
}
