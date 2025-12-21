import SwiftUI

struct AnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat
    let isEditing: Bool
    let onUpdate: (Annotation) -> Void

    @State private var editableText: String = ""

    var body: some View {
        Group {
            switch annotation.type {
            case .arrow:
                ArrowAnnotationView(annotation: annotation, scale: scale)

            case .line:
                LineAnnotationView(annotation: annotation, scale: scale)

            case .rectangle:
                RectangleAnnotationView(annotation: annotation, scale: scale)

            case .circle:
                CircleAnnotationView(annotation: annotation, scale: scale)

            case .freehand:
                FreehandAnnotationView(annotation: annotation, scale: scale)

            case .highlighter:
                HighlighterAnnotationView(annotation: annotation, scale: scale)

            case .text:
                TextAnnotationView(
                    annotation: annotation,
                    scale: scale,
                    isEditing: isEditing,
                    onUpdate: onUpdate
                )

            case .blur:
                BlurAnnotationView(annotation: annotation, scale: scale)

            case .numberedStep:
                NumberedStepAnnotationView(annotation: annotation, scale: scale)

            case .callout:
                CalloutAnnotationView(annotation: annotation, scale: scale)

            case .crop:
                CropAnnotationView(annotation: annotation, scale: scale)
            }
        }
    }
}

// MARK: - Arrow Annotation
struct ArrowAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return }

            let scaledStart = CGPoint(x: start.x * scale, y: start.y * scale)
            let scaledEnd = CGPoint(x: end.x * scale, y: end.y * scale)

            // Draw line
            var path = Path()
            path.move(to: scaledStart)
            path.addLine(to: scaledEnd)

            context.stroke(
                path,
                with: .color(annotation.color),
                lineWidth: annotation.strokeWidth * scale
            )

            // Draw arrowhead
            let angle = atan2(scaledEnd.y - scaledStart.y, scaledEnd.x - scaledStart.x)
            let arrowLength: CGFloat = 15 * scale
            let arrowAngle: CGFloat = .pi / 6

            var arrowPath = Path()
            arrowPath.move(to: scaledEnd)
            arrowPath.addLine(to: CGPoint(
                x: scaledEnd.x - arrowLength * cos(angle - arrowAngle),
                y: scaledEnd.y - arrowLength * sin(angle - arrowAngle)
            ))
            arrowPath.move(to: scaledEnd)
            arrowPath.addLine(to: CGPoint(
                x: scaledEnd.x - arrowLength * cos(angle + arrowAngle),
                y: scaledEnd.y - arrowLength * sin(angle + arrowAngle)
            ))

            context.stroke(
                arrowPath,
                with: .color(annotation.color),
                style: StrokeStyle(lineWidth: annotation.strokeWidth * scale, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Line Annotation
struct LineAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return }

            var path = Path()
            path.move(to: CGPoint(x: start.x * scale, y: start.y * scale))
            path.addLine(to: CGPoint(x: end.x * scale, y: end.y * scale))

            context.stroke(
                path,
                with: .color(annotation.color),
                style: StrokeStyle(lineWidth: annotation.strokeWidth * scale, lineCap: .round)
            )
        }
    }
}

// MARK: - Rectangle Annotation
struct RectangleAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: annotation.frame.width * scale,
            height: annotation.frame.height * scale
        )

        Rectangle()
            .strokeBorder(annotation.color, lineWidth: annotation.strokeWidth * scale)
            .frame(width: scaledRect.width, height: scaledRect.height)
            .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - Circle Annotation
struct CircleAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: annotation.frame.width * scale,
            height: annotation.frame.height * scale
        )

        Ellipse()
            .strokeBorder(annotation.color, lineWidth: annotation.strokeWidth * scale)
            .frame(width: scaledRect.width, height: scaledRect.height)
            .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - Freehand Annotation
struct FreehandAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            guard annotation.points.count > 1 else { return }

            var path = Path()
            let scaledPoints = annotation.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }

            path.move(to: scaledPoints[0])
            for point in scaledPoints.dropFirst() {
                path.addLine(to: point)
            }

            context.stroke(
                path,
                with: .color(annotation.color),
                style: StrokeStyle(lineWidth: annotation.strokeWidth * scale, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Highlighter Annotation
struct HighlighterAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            guard annotation.points.count > 1 else { return }

            var path = Path()
            let scaledPoints = annotation.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }

            path.move(to: scaledPoints[0])
            for point in scaledPoints.dropFirst() {
                path.addLine(to: point)
            }

            context.stroke(
                path,
                with: .color(annotation.color.opacity(0.4)),
                style: StrokeStyle(lineWidth: annotation.strokeWidth * scale, lineCap: .round, lineJoin: .round)
            )
        }
        .blendMode(.multiply)
    }
}

// MARK: - Text Annotation
struct TextAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat
    let isEditing: Bool
    let onUpdate: (Annotation) -> Void

    @State private var text: String = ""

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: annotation.frame.width * scale,
            height: annotation.frame.height * scale
        )

        Group {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: (annotation.fontSize ?? 16) * scale))
                    .foregroundColor(annotation.color)
                    .onSubmit {
                        var updated = annotation
                        updated.text = text
                        onUpdate(updated)
                    }
                    .onAppear {
                        text = annotation.text ?? ""
                    }
            } else {
                Text(annotation.text ?? "")
                    .font(.system(size: (annotation.fontSize ?? 16) * scale))
                    .foregroundColor(annotation.color)
            }
        }
        .position(x: scaledRect.minX + scaledRect.width / 2, y: scaledRect.minY + scaledRect.height / 2)
    }
}

// MARK: - Blur Annotation
struct BlurAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: annotation.frame.width * scale,
            height: annotation.frame.height * scale
        )

        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(width: scaledRect.width, height: scaledRect.height)
            .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - Numbered Step Annotation
struct NumberedStepAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: 30 * scale,
            height: 30 * scale
        )

        ZStack {
            Circle()
                .fill(annotation.color)
                .frame(width: scaledRect.width, height: scaledRect.height)

            Text("\(annotation.stepNumber ?? 1)")
                .font(.system(size: 16 * scale, weight: .bold))
                .foregroundColor(.white)
        }
        .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - Callout Annotation
struct CalloutAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: annotation.frame.width * scale,
            height: annotation.frame.height * scale
        )

        ZStack {
            // Background bubble
            RoundedRectangle(cornerRadius: 8 * scale)
                .fill(annotation.color.opacity(0.9))
                .frame(width: scaledRect.width, height: scaledRect.height)

            // Text
            Text(annotation.text ?? "Callout")
                .font(.system(size: (annotation.fontSize ?? 14) * scale))
                .foregroundColor(.white)
                .padding(8 * scale)
        }
        .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - Crop Annotation
struct CropAnnotationView: View {
    let annotation: Annotation
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: annotation.frame.origin.x * scale,
            y: annotation.frame.origin.y * scale,
            width: annotation.frame.width * scale,
            height: annotation.frame.height * scale
        )

        ZStack {
            // Darkened outside area would be handled differently
            // This just shows the selection

            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                .foregroundColor(.white)
                .frame(width: scaledRect.width, height: scaledRect.height)

            // Corner handles
            ForEach(0..<4, id: \.self) { index in
                let x: CGFloat = index % 2 == 0 ? 0 : scaledRect.width
                let y: CGFloat = index < 2 ? 0 : scaledRect.height

                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .position(x: x, y: y)
            }
        }
        .frame(width: scaledRect.width, height: scaledRect.height)
        .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

#Preview {
    VStack {
        AnnotationView(
            annotation: Annotation(
                type: .arrow,
                frame: CGRect(x: 50, y: 50, width: 100, height: 100),
                color: .red,
                strokeWidth: 3,
                startPoint: CGPoint(x: 50, y: 50),
                endPoint: CGPoint(x: 150, y: 150)
            ),
            scale: 1.0,
            isEditing: false,
            onUpdate: { _ in }
        )
        .frame(width: 200, height: 200)
        .background(Color.gray.opacity(0.2))
    }
}
