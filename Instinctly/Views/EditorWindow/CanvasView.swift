import SwiftUI
import AppKit

struct CanvasView: View {
    let image: NSImage
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @EnvironmentObject private var appState: AppState

    @State private var currentAnnotation: Annotation?
    @State private var dragStart: CGPoint?
    @State private var isDrawing = false
    @State private var freehandPoints: [CGPoint] = []
    @State private var textEditingAnnotation: UUID?
    @State private var imageOrigin: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageWidth = image.size.width * scale
            let imageHeight = image.size.height * scale
            let contentWidth = max(geometry.size.width, imageWidth)
            let contentHeight = max(geometry.size.height, imageHeight)
            // Calculate image offset when centered
            let imageOffsetX = (contentWidth - imageWidth) / 2
            let imageOffsetY = (contentHeight - imageHeight) / 2

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    // Base image
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageWidth, height: imageHeight)

                    // Annotations layer
                    AnnotationsOverlay(
                        annotations: appState.annotations,
                        currentAnnotation: currentAnnotation,
                        scale: scale,
                        textEditingAnnotation: $textEditingAnnotation,
                        onAnnotationUpdate: { updated in
                            appState.saveToHistory()
                            if let index = appState.annotations.firstIndex(where: { $0.id == updated.id }) {
                                appState.annotations[index] = updated
                            }
                        }
                    )
                    .frame(width: imageWidth, height: imageHeight)

                    // Drawing overlay (for capturing gestures)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawingGesture)
                        .gesture(tapGesture)
                        .frame(width: imageWidth, height: imageHeight)
                }
                .frame(width: contentWidth, height: contentHeight)
            }
            .onAppear {
                imageOrigin = CGPoint(x: imageOffsetX, y: imageOffsetY)
            }
            .onChange(of: scale) { _, _ in
                imageOrigin = CGPoint(x: imageOffsetX, y: imageOffsetY)
            }
        }
    }

    // MARK: - Tap Gesture (attached directly to image area)
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleTap(at: value.location)
            }
    }

    // MARK: - Drawing Gesture

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = value.location
                let scaledPoint = CGPoint(x: point.x / scale, y: point.y / scale)

                switch appState.selectedTool {
                case .arrow, .line, .rectangle, .circle:
                    handleShapeDrag(start: value.startLocation, current: point)

                case .freehand, .highlighter:
                    handleFreehandDrag(point: scaledPoint)

                case .blur:
                    handleBlurDrag(start: value.startLocation, current: point)

                case .crop:
                    handleCropDrag(start: value.startLocation, current: point)

                case .colorPicker:
                    // Color picking handled on tap
                    break

                default:
                    break
                }
            }
            .onEnded { value in
                finishDrawing()
            }
    }

    // MARK: - Shape Drawing

    private func handleShapeDrag(start: CGPoint, current: CGPoint) {
        let scaledStart = CGPoint(x: start.x / scale, y: start.y / scale)
        let scaledCurrent = CGPoint(x: current.x / scale, y: current.y / scale)

        if dragStart == nil {
            dragStart = scaledStart
        }

        let rect = CGRect(
            x: min(scaledStart.x, scaledCurrent.x),
            y: min(scaledStart.y, scaledCurrent.y),
            width: abs(scaledCurrent.x - scaledStart.x),
            height: abs(scaledCurrent.y - scaledStart.y)
        )

        currentAnnotation = Annotation(
            type: annotationTypeForTool(appState.selectedTool),
            frame: rect,
            color: appState.selectedColor,
            strokeWidth: appState.strokeWidth,
            startPoint: scaledStart,
            endPoint: scaledCurrent
        )
    }

    // MARK: - Freehand Drawing

    private func handleFreehandDrag(point: CGPoint) {
        freehandPoints.append(point)

        currentAnnotation = Annotation(
            type: appState.selectedTool == .highlighter ? .highlighter : .freehand,
            frame: boundingRect(for: freehandPoints),
            color: appState.selectedColor,
            strokeWidth: appState.selectedTool == .highlighter ? 20 : appState.strokeWidth,
            points: freehandPoints
        )
    }

    // MARK: - Blur

    private func handleBlurDrag(start: CGPoint, current: CGPoint) {
        let scaledStart = CGPoint(x: start.x / scale, y: start.y / scale)
        let scaledCurrent = CGPoint(x: current.x / scale, y: current.y / scale)

        let rect = CGRect(
            x: min(scaledStart.x, scaledCurrent.x),
            y: min(scaledStart.y, scaledCurrent.y),
            width: abs(scaledCurrent.x - scaledStart.x),
            height: abs(scaledCurrent.y - scaledStart.y)
        )

        currentAnnotation = Annotation(
            type: .blur,
            frame: rect,
            color: .clear,
            strokeWidth: 0
        )
    }

    // MARK: - Crop

    private func handleCropDrag(start: CGPoint, current: CGPoint) {
        let scaledStart = CGPoint(x: start.x / scale, y: start.y / scale)
        let scaledCurrent = CGPoint(x: current.x / scale, y: current.y / scale)

        let rect = CGRect(
            x: min(scaledStart.x, scaledCurrent.x),
            y: min(scaledStart.y, scaledCurrent.y),
            width: abs(scaledCurrent.x - scaledStart.x),
            height: abs(scaledCurrent.y - scaledStart.y)
        )

        currentAnnotation = Annotation(
            type: .crop,
            frame: rect,
            color: .white,
            strokeWidth: 2
        )
    }

    // MARK: - Finish Drawing

    private func finishDrawing() {
        if let annotation = currentAnnotation {
            // Don't add if too small
            if annotation.frame.width > 5 || annotation.frame.height > 5 || !annotation.points.isEmpty {
                if annotation.type == .crop {
                    // Apply crop
                    appState.saveToHistory()
                    applyCrop(rect: annotation.frame)
                } else {
                    appState.saveToHistory()
                    appState.annotations.append(annotation)
                }
            }
        }

        currentAnnotation = nil
        dragStart = nil
        freehandPoints = []
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        let scaledPoint = CGPoint(x: location.x / scale, y: location.y / scale)

        switch appState.selectedTool {
        case .text:
            addTextAnnotation(at: scaledPoint)

        case .numberedStep:
            addNumberedStep(at: scaledPoint)

        case .colorPicker:
            pickColor(at: scaledPoint)

        case .select:
            selectAnnotation(at: scaledPoint)

        default:
            break
        }
    }

    private func addTextAnnotation(at point: CGPoint) {
        let annotation = Annotation(
            type: .text,
            frame: CGRect(origin: point, size: CGSize(width: 200, height: 30)),
            color: appState.selectedColor,
            strokeWidth: appState.strokeWidth,
            text: "Text",
            fontSize: appState.fontSize
        )
        appState.saveToHistory()
        appState.annotations.append(annotation)
        textEditingAnnotation = annotation.id
    }

    private func addNumberedStep(at point: CGPoint) {
        let stepNumber = appState.annotations.filter { $0.type == .numberedStep }.count + 1
        let annotation = Annotation(
            type: .numberedStep,
            frame: CGRect(origin: point, size: CGSize(width: 30, height: 30)),
            color: appState.selectedColor,
            strokeWidth: appState.strokeWidth,
            stepNumber: stepNumber
        )
        appState.saveToHistory()
        appState.annotations.append(annotation)
    }

    private func pickColor(at point: CGPoint) {
        // Get color from image at point
        if let color = ColorExtractor.getColor(from: image, at: point) {
            appState.selectedColor = Color(nsColor: color)
        }
    }

    private func selectAnnotation(at point: CGPoint) {
        // Find annotation at point
        for annotation in appState.annotations.reversed() {
            if annotation.frame.contains(point) {
                // Select this annotation
                // TODO: Implement selection state
                break
            }
        }
    }

    private func applyCrop(rect: CGRect) {
        guard let croppedImage = ImageProcessingService.cropImage(image, to: rect) else { return }
        appState.currentImage = croppedImage
        appState.annotations = []
    }

    // MARK: - Helpers

    private func annotationTypeForTool(_ tool: AnnotationTool) -> AnnotationType {
        switch tool {
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .circle: return .circle
        case .freehand: return .freehand
        case .highlighter: return .highlighter
        case .text: return .text
        case .blur: return .blur
        case .numberedStep: return .numberedStep
        case .callout: return .callout
        case .crop: return .crop
        default: return .rectangle
        }
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Annotations Overlay
struct AnnotationsOverlay: View {
    let annotations: [Annotation]
    let currentAnnotation: Annotation?
    let scale: CGFloat
    @Binding var textEditingAnnotation: UUID?
    let onAnnotationUpdate: (Annotation) -> Void

    var body: some View {
        ZStack {
            ForEach(annotations) { annotation in
                AnnotationView(
                    annotation: annotation,
                    scale: scale,
                    isEditing: textEditingAnnotation == annotation.id,
                    onUpdate: onAnnotationUpdate
                )
            }

            if let current = currentAnnotation {
                AnnotationView(
                    annotation: current,
                    scale: scale,
                    isEditing: false,
                    onUpdate: { _ in }
                )
                .opacity(0.8)
            }
        }
    }
}

#Preview {
    CanvasView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        scale: .constant(1.0),
        offset: .constant(.zero)
    )
    .environmentObject(AppState.shared)
}
