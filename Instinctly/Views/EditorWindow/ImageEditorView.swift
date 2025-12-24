import SwiftUI

struct ImageEditorView: View {
    let imageId: UUID?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var showExportSheet = false
    @State private var showShareSheet = false
    @State private var showColorPicker = false

    var body: some View {
        HStack(spacing: 0) {
            // Left Toolbar
            ToolbarView()

            // Main Canvas Area
            VStack(spacing: 0) {
                // Top bar
                EditorTopBar(
                    showExportSheet: $showExportSheet,
                    showShareSheet: $showShareSheet,
                    onClose: {
                        // Clear the current image and go back to welcome screen
                        appState.currentImage = nil
                        appState.annotations = []
                    }
                )

                // Canvas
                ZStack {
                    // Background
                    Color(nsColor: .textBackgroundColor)

                    // Image Canvas
                    if let image = appState.currentImage {
                        CanvasView(
                            image: image,
                            scale: $scale,
                            offset: $offset
                        )
                    } else {
                        EmptyCanvasView()
                    }
                }

                // Bottom status bar
                EditorBottomBar(scale: $scale)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showExportSheet) {
            ExportOptionsSheet()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = appState.currentImage {
                ShareSheet(image: image, annotations: appState.annotations)
            }
        }
        .onAppear {
            setupKeyboardShortcuts()
        }
    }

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Skip shortcuts if a text field is being edited
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                // Check if text input is active (NSTextField, NSTextView, NSSecureTextField, etc.)
                if firstResponder is NSTextView ||
                   firstResponder.isKind(of: NSClassFromString("NSTextInputContext")!) == true ||
                   String(describing: type(of: firstResponder)).contains("TextField") {
                    return event // Let the text field handle the event
                }
            }

            // Tool shortcuts (only single character without modifiers)
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty ||
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .capsLock {
                for tool in AnnotationTool.allCases {
                    if let shortcut = tool.shortcut,
                       event.charactersIgnoringModifiers == String(shortcut.character) {
                        appState.selectedTool = tool
                        return nil
                    }
                }
            }

            // Undo: Cmd+Z, Redo: Cmd+Shift+Z
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
                if event.modifierFlags.contains(.shift) {
                    appState.redo()
                } else {
                    appState.undo()
                }
                return nil
            }

            return event
        }
    }
}

// MARK: - Editor Top Bar
struct EditorTopBar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showExportSheet: Bool
    @Binding var showShareSheet: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.06))
            .clipShape(Circle())
            .help("Close")

            // Undo/Redo
            HStack(spacing: 2) {
                Button(action: { appState.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .disabled(!appState.canUndo)
                .opacity(appState.canUndo ? 1 : 0.4)
                .help("Undo (⌘Z)")

                Button(action: { appState.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .disabled(!appState.canRedo)
                .opacity(appState.canRedo ? 1 : 0.4)
                .help("Redo (⌘⇧Z)")
            }

            Spacer()

            // Recording button
            QuickRecordButton()
                .help("Record Screen")

            // Share & Export options
            HStack(spacing: 6) {
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy to clipboard (⌘C)")

                Button(action: { showShareSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Share (⌘⇧S)")

                Button(action: { showExportSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Save (⌘S)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    private func copyToClipboard() {
        guard let image = appState.currentImage else { return }

        // Render annotations onto image
        let finalImage = ImageProcessingService.renderAnnotations(
            on: image,
            annotations: appState.annotations
        )

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }
}

// MARK: - Editor Bottom Bar
struct EditorBottomBar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var scale: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            // Image dimensions
            if let image = appState.currentImage {
                Text("\(Int(image.size.width))×\(Int(image.size.height))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Button(action: { scale = max(0.25, scale - 0.25) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)

                Text("\(Int(scale * 100))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 36)

                Button(action: { scale = min(4.0, scale + 0.25) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
    }
}

// MARK: - Empty Canvas View
struct EmptyCanvasView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No image loaded")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Capture a screenshot or paste an image from clipboard")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Checkerboard Background
struct CheckerboardBackground: View {
    let tileSize: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let columns = Int(geometry.size.width / tileSize) + 1
            let rows = Int(geometry.size.height / tileSize) + 1

            Canvas { context, size in
                for row in 0..<rows {
                    for col in 0..<columns {
                        let isLight = (row + col) % 2 == 0
                        let rect = CGRect(
                            x: CGFloat(col) * tileSize,
                            y: CGFloat(row) * tileSize,
                            width: tileSize,
                            height: tileSize
                        )
                        context.fill(
                            Path(rect),
                            with: .color(isLight ? Color.gray.opacity(0.2) : Color.gray.opacity(0.3))
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    ImageEditorView(imageId: nil)
        .environmentObject(AppState.shared)
}
