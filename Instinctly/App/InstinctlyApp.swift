import SwiftUI
import AppKit
import Combine

@main
struct InstinctlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // Main window (opens when clicking dock icon)
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 600)

        // Menu bar app
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.window)

        // Editor window
        WindowGroup(id: "editor", for: UUID.self) { $imageId in
            ImageEditorView(imageId: imageId)
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Settings
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentImage: NSImage?
    @Published var selectedTool: AnnotationTool = .arrow
    @Published var selectedColor: Color = .red
    @Published var strokeWidth: CGFloat = 3.0
    @Published var fontSize: CGFloat = 16.0
    @Published var annotations: [Annotation] = []
    @Published var isCapturing: Bool = false

    // Undo/Redo history
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private let maxHistorySize = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private init() {}

    func reset() {
        currentImage = nil
        annotations = []
        undoStack = []
        redoStack = []
    }

    // MARK: - History Management

    /// Save current state before making changes
    func saveToHistory() {
        undoStack.append(annotations)
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }
        redoStack.removeAll() // Clear redo stack on new action
    }

    /// Undo last annotation change
    func undo() {
        guard canUndo else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
    }

    /// Redo previously undone change
    func redo() {
        guard canRedo else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
    }
}

// MARK: - Annotation Tool Enum
enum AnnotationTool: String, CaseIterable, Identifiable {
    case select = "Select"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Rectangle"
    case circle = "Circle"
    case freehand = "Freehand"
    case highlighter = "Highlighter"
    case text = "Text"
    case blur = "Blur"
    case numberedStep = "Step"
    case callout = "Callout"
    case crop = "Crop"
    case colorPicker = "Color Picker"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .freehand: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .numberedStep: return "1.circle"
        case .callout: return "text.bubble"
        case .crop: return "crop"
        case .colorPicker: return "eyedropper"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .circle: return "o"
        case .freehand: return "p"
        case .highlighter: return "h"
        case .text: return "t"
        case .blur: return "b"
        case .numberedStep: return "n"
        case .callout: return "c"
        case .crop: return "x"
        case .colorPicker: return "i"
        }
    }
}
