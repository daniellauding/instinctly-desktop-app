import SwiftUI
import ScreenCaptureKit

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var captureService = ScreenCaptureService()
    @StateObject private var recordingService = ScreenRecordingService.shared
    @State private var showWindowPicker = false
    @State private var showNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var customProjects: [String] = []

    init() {
        // Load saved projects
        _customProjects = State(initialValue: UserDefaults.standard.stringArray(forKey: "customProjects") ?? [])
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("Quick Actions") {
                    Button(action: captureRegion) {
                        Label("Capture Region", systemImage: "rectangle.dashed")
                    }

                    Button(action: captureWindow) {
                        Label("Capture Window", systemImage: "macwindow")
                    }

                    Button(action: captureFullScreen) {
                        Label("Capture Full Screen", systemImage: "rectangle.on.rectangle")
                    }

                    Button(action: openFromClipboard) {
                        Label("Open from Clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                Section("Recording") {
                    SidebarRecordButton(title: "Record Region", icon: "rectangle.dashed.badge.record", mode: .region)
                    SidebarRecordButton(title: "Record Window", icon: "macwindow.badge.plus", mode: .window)
                    SidebarRecordButton(title: "Record Full Screen", icon: "rectangle.inset.filled.badge.record", mode: .fullScreen)
                    SidebarRecordButton(title: "Voice Only", icon: "mic.fill", mode: .voiceOnly)
                }

                Section("Library") {
                    NavigationLink(value: "all") {
                        Label("All Images", systemImage: "photo.on.rectangle")
                    }

                    NavigationLink(value: "screenshots") {
                        Label("Screenshots", systemImage: "camera.viewfinder")
                    }

                    NavigationLink(value: "favorites") {
                        Label("Favorites", systemImage: "star")
                    }
                }

                if !customProjects.isEmpty {
                    Section("Projects") {
                        ForEach(customProjects, id: \.self) { project in
                            NavigationLink(value: project) {
                                Label(project, systemImage: "folder")
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteProject(project)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(action: { showNewProjectSheet = true }) {
                        Label("New Project", systemImage: "plus.circle")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            // Main content
            VStack(spacing: 0) {
                if appState.currentImage != nil {
                    // Show editor if image is loaded
                    ImageEditorView(imageId: nil)
                } else {
                    // Welcome/empty state
                    WelcomeView(
                        onCaptureRegion: captureRegion,
                        onCaptureWindow: captureWindow,
                        onCaptureFullScreen: captureFullScreen,
                        onOpenFromClipboard: openFromClipboard
                    )
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: captureRegion) {
                    Label("Capture", systemImage: "camera.viewfinder")
                }
                .help("Capture Region (⌘⇧4)")
            }
        }
        .sheet(isPresented: $showWindowPicker) {
            WindowPickerView { selectedWindow in
                captureSelectedWindow(selectedWindow)
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            MainWindowNewProjectSheet(
                projectName: $newProjectName,
                onCreate: createNewProject,
                onCancel: {
                    newProjectName = ""
                    showNewProjectSheet = false
                }
            )
        }
    }

    // MARK: - Project Management

    private func createNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if !customProjects.contains(name) {
            customProjects.append(name)
            saveProjects()
        }
        newProjectName = ""
        showNewProjectSheet = false
    }

    private func deleteProject(_ name: String) {
        customProjects.removeAll { $0 == name }
        saveProjects()
    }

    private func saveProjects() {
        UserDefaults.standard.set(customProjects, forKey: "customProjects")
    }

    // MARK: - Actions

    private func captureRegion() {
        Task {
            do {
                let image = try await captureService.captureRegion()
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func captureWindow() {
        showWindowPicker = true
    }

    private func captureSelectedWindow(_ window: SCWindow) {
        Task {
            do {
                let image = try await captureService.captureWindow(window)
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func captureFullScreen() {
        Task {
            do {
                let image = try await captureService.captureFullScreen()
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func openFromClipboard() {
        if let data = NSPasteboard.general.data(forType: .tiff),
           let image = NSImage(data: data) {
            appState.currentImage = image
            appState.annotations = []
        } else if let data = NSPasteboard.general.data(forType: .png),
                  let image = NSImage(data: data) {
            appState.currentImage = image
            appState.annotations = []
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    let onCaptureRegion: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureFullScreen: () -> Void
    let onOpenFromClipboard: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/logo
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Welcome to Instinctly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Capture, annotate, and share screenshots")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Quick action buttons
            HStack(spacing: 20) {
                QuickActionCard(
                    title: "Capture Region",
                    subtitle: "⌘⇧3",
                    icon: "rectangle.dashed",
                    action: onCaptureRegion
                )

                QuickActionCard(
                    title: "Capture Window",
                    subtitle: "⌘⇧4",
                    icon: "macwindow",
                    action: onCaptureWindow
                )

                QuickActionCard(
                    title: "Full Screen",
                    subtitle: "⌘⇧5",
                    icon: "rectangle.on.rectangle",
                    action: onCaptureFullScreen
                )

                QuickActionCard(
                    title: "From Clipboard",
                    subtitle: "⌘⇧6",
                    icon: "doc.on.clipboard",
                    action: onOpenFromClipboard
                )
            }
            .padding(.top, 20)

            Spacer()

            // Keyboard shortcuts hint
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                Text("Use global keyboard shortcuts to capture from anywhere")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isHovered ? .primary : .secondary)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Sidebar Record Button
struct SidebarRecordButton: View {
    let title: String
    let icon: String
    let mode: RecordingConfiguration.CaptureMode

    @StateObject private var recordingService = ScreenRecordingService.shared

    private var isThisModeRecording: Bool {
        recordingService.state.isRecording && recordingService.configuration.captureMode == mode
    }

    var body: some View {
        Button(action: handleTap) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundColor(mode == .voiceOnly ? .blue : .red)

                Spacer()

                if isThisModeRecording {
                    Text(formatTime(recordingService.elapsedTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.red)
                }
            }
        }
        .disabled(recordingService.state.isRecording && !isThisModeRecording)
    }

    private func handleTap() {
        if isThisModeRecording {
            // Stop recording
            Task {
                _ = try? await recordingService.stopRecording()
            }
        } else {
            // Start recording
            startRecording()
        }
    }

    private func startRecording() {
        recordingService.configuration.captureMode = mode

        switch mode {
        case .region:
            Task { @MainActor in
                print("🎬 Sidebar: Starting region selection...")
                let selector = RecordingRegionSelector()
                if let region = await selector.selectRegion() {
                    print("🎬 Sidebar: Region selected: \(region)")
                    recordingService.configuration.region = region
                    do {
                        try await recordingService.startRecording()
                        print("🎬 Sidebar: Recording started!")
                    } catch {
                        print("❌ Sidebar: Failed to start recording: \(error)")
                    }
                }
            }

        case .window:
            Task { @MainActor in
                print("🎬 Sidebar: Starting window recording...")
                do {
                    try await recordingService.startRecording()
                } catch {
                    print("❌ Sidebar: Failed to start recording: \(error)")
                }
            }

        case .fullScreen, .voiceOnly:
            Task {
                print("🎬 Sidebar: Starting \(mode.rawValue) recording...")
                do {
                    try await recordingService.startRecording()
                } catch {
                    print("❌ Sidebar: Failed to start recording: \(error)")
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Main Window New Project Sheet
struct MainWindowNewProjectSheet: View {
    @Binding var projectName: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            TextField("Project Name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit {
                    if !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCreate()
                    }
                }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    onCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            isNameFocused = true
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState.shared)
        .frame(width: 900, height: 600)
}
