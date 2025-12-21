import CoreGraphics

extension CGPoint {
    /// Calculate distance to another point
    func distance(to point: CGPoint) -> CGFloat {
        let dx = x - point.x
        let dy = y - point.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Calculate angle to another point (in radians)
    func angle(to point: CGPoint) -> CGFloat {
        atan2(point.y - y, point.x - x)
    }

    /// Get midpoint between this point and another
    func midpoint(to point: CGPoint) -> CGPoint {
        CGPoint(
            x: (x + point.x) / 2,
            y: (y + point.y) / 2
        )
    }

    /// Create a new point offset by dx and dy
    func offset(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    /// Create a new point at a distance and angle from this point
    func point(at distance: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: x + distance * cos(angle),
            y: y + distance * sin(angle)
        )
    }

    /// Scale point by a factor
    func scaled(by factor: CGFloat) -> CGPoint {
        CGPoint(x: x * factor, y: y * factor)
    }

    /// Check if point is within a rect
    func isWithin(_ rect: CGRect) -> Bool {
        rect.contains(self)
    }

    /// Clamp point to be within a rect
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}

extension CGSize {
    /// Calculate aspect ratio (width / height)
    var aspectRatio: CGFloat {
        guard height > 0 else { return 0 }
        return width / height
    }

    /// Scale size to fit within max dimensions while maintaining aspect ratio
    func scaled(toFit maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / width
        let heightRatio = maxSize.height / height
        let ratio = min(widthRatio, heightRatio)

        return CGSize(
            width: width * ratio,
            height: height * ratio
        )
    }

    /// Scale size to fill max dimensions while maintaining aspect ratio
    func scaled(toFill maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / width
        let heightRatio = maxSize.height / height
        let ratio = max(widthRatio, heightRatio)

        return CGSize(
            width: width * ratio,
            height: height * ratio
        )
    }
}

extension CGRect {
    /// Get center point of rect
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    /// Create rect from center point and size
    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Get corner points
    var corners: [CGPoint] {
        [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
    }

    /// Scale rect by factor from center
    func scaled(by factor: CGFloat) -> CGRect {
        let newWidth = width * factor
        let newHeight = height * factor

        return CGRect(
            x: midX - newWidth / 2,
            y: midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
    }

    /// Expand rect by amount on all sides
    func expanded(by amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }

    /// Normalize rect (ensure positive width and height)
    var normalized: CGRect {
        CGRect(
            x: width < 0 ? origin.x + width : origin.x,
            y: height < 0 ? origin.y + height : origin.y,
            width: abs(width),
            height: abs(height)
        )
    }
}
