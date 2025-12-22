import SwiftUI
import ScreenCaptureKit

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var captureService = ScreenCaptureService()
    @StateObject private var recordingService = ScreenRecordingService.shared
    @StateObject private var libraryService = LibraryService.shared
    @State private var showWindowPicker = false
    @State private var showNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var selectedCollection: String? = nil

    // Custom collections (excluding built-in ones)
    private var customProjects: [String] {
        libraryService.collections.filter { !["Screenshots", "Recordings", "Favorites"].contains($0) }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedCollection) {
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
                    NavigationLink(value: "All") {
                        Label("All Images", systemImage: "photo.on.rectangle")
                    }

                    NavigationLink(value: "Screenshots") {
                        Label("Screenshots", systemImage: "camera.viewfinder")
                    }

                    NavigationLink(value: "Recordings") {
                        Label("Recordings", systemImage: "video")
                    }

                    NavigationLink(value: "Favorites") {
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
            // Main content - show library grid or editor
            if appState.currentImage != nil {
                // Show editor if image is loaded
                ImageEditorView(imageId: nil)
            } else if let collection = selectedCollection {
                // Show library items for selected collection
                LibraryGridView(collection: collection, libraryService: libraryService, appState: appState)
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.currentImage != nil {
                    Button(action: { appState.currentImage = nil }) {
                        Label("Back to Library", systemImage: "arrow.left")
                    }
                    .help("Back to Library")
                }

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
        libraryService.addCollection(name)
        newProjectName = ""
        showNewProjectSheet = false
        selectedCollection = name
    }

    private func deleteProject(_ name: String) {
        libraryService.removeCollection(name)
        if selectedCollection == name {
            selectedCollection = nil
        }
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

// MARK: - Library Grid View
struct LibraryGridView: View {
    let collection: String
    @ObservedObject var libraryService: LibraryService
    @ObservedObject var appState: AppState

    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    private var items: [LibraryItem] {
        var result = libraryService.items(in: collection)
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search \(collection)...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding()

            Divider()

            if items.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No items in \(collection)")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Save screenshots or recordings to see them here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Grid of items
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            LibraryItemCard(item: item, libraryService: libraryService, appState: appState)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Library Item Card
struct LibraryItemCard: View {
    let item: LibraryItem
    @ObservedObject var libraryService: LibraryService
    @ObservedObject var appState: AppState

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/10, contentMode: .fit)

                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: iconForType)
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }

                if isHovered {
                    Color.black.opacity(0.4)
                        .cornerRadius(8)

                    VStack(spacing: 8) {
                        // Open in editor
                        Button(action: openInEditor) {
                            Label("Edit", systemImage: "pencil")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 8) {
                            // Favorite
                            Button(action: { libraryService.toggleFavorite(item) }) {
                                Image(systemName: item.isFavorite ? "star.fill" : "star")
                                    .foregroundColor(item.isFavorite ? .yellow : .white)
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            // Open in Finder
                            Button(action: openInFinder) {
                                Image(systemName: "folder")
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            // Delete
                            Button(action: { libraryService.deleteItem(item) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .onTapGesture(count: 2) {
                openInEditor()
            }

            // Info
            HStack(spacing: 4) {
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Text(dateFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private var iconForType: String {
        switch item.type {
        case .screenshot: return "photo"
        case .recording: return "video"
        case .gif: return "photo.stack"
        case .voiceRecording: return "waveform"
        }
    }

    private var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.createdAt)
    }

    private func loadThumbnail() {
        if item.type == .screenshot {
            thumbnail = libraryService.loadImage(for: item)
        }
    }

    private func openInEditor() {
        if item.type == .screenshot, let image = libraryService.loadImage(for: item) {
            appState.currentImage = image
            appState.annotations = []
        } else {
            // Open in default app
            let url = libraryService.fileURL(for: item)
            NSWorkspace.shared.open(url)
        }
    }

    private func openInFinder() {
        let url = libraryService.fileURL(for: item)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState.shared)
        .frame(width: 900, height: 600)
}
