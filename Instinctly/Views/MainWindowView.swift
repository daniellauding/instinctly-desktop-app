import SwiftUI
import ScreenCaptureKit
import AVFoundation
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Notification Helper
struct NotificationHelper {
    static func showNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        
        // Request permission if needed
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("❌ Failed to request notification permission: \(error)")
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Create request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        // Schedule notification
        do {
            try await center.add(request)
        } catch {
            print("❌ Failed to show notification: \(error)")
        }
    }
}

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

    // Project editing
    @State private var showEditProjectSheet = false
    @State private var editingProject: String?
    @State private var editProjectName = ""
    @State private var editProjectDescription = ""
    @State private var editProjectIsPublic = false
    @State private var editProjectPassword = ""
    @State private var isSavingProject = false
    @State private var showDeleteProjectConfirm = false
    @State private var projectToDelete: String?

    // Custom collections (excluding built-in ones)
    private var customProjects: [String] {
        libraryService.collections.filter { !["Screenshots", "Recordings", "Favorites"].contains($0) }
    }

    // Sync status text
    private var syncStatusText: String {
        switch libraryService.syncStatus {
        case .idle:
            return libraryService.iCloudAvailable ? "Ready" : "iCloud not available"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "\(libraryService.items.count) items"
        case .error(let msg):
            return "Error: \(msg)"
        }
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
                    SidebarRecordButton(title: "Record GIF", icon: "photo.stack", mode: .region, forceGif: true)
                    SidebarRecordButton(title: "Record Region with Webcam", icon: "rectangle.dashed.and.paperclip", mode: .region, withWebcam: true)
                    SidebarRecordButton(title: "Record Selected Window with Webcam", icon: "macwindow.and.cursorarrow", mode: .window, withWebcam: true)
                    SidebarRecordButton(title: "Record Full Screen with Webcam", icon: "rectangle.inset.filled.and.person.filled", mode: .fullScreen, withWebcam: true)
                    SidebarRecordButton(title: "Voice Only", icon: "mic.fill", mode: .voiceOnly)
                }

                Section("Recent") {
                    NavigationLink(value: "Recent") {
                        Label("Recent Files", systemImage: "clock")
                    }
                }
                Section("Shared") {
                    NavigationLink(value: "Shared") {
                        Label("Shared Links", systemImage: "link.circle")
                    }
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
                                Button {
                                    editingProject = project
                                    editProjectName = project
                                    showEditProjectSheet = true
                                } label: {
                                    Label("Edit Project...", systemImage: "pencil")
                                }

                                Button {
                                    editingProject = project
                                    editProjectName = project
                                    showEditProjectSheet = true
                                } label: {
                                    Label("Share Project...", systemImage: "square.and.arrow.up")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    projectToDelete = project
                                    showDeleteProjectConfirm = true
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

                // iCloud Sync Status
                Section {
                    HStack {
                        Image(systemName: libraryService.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                            .foregroundColor(libraryService.iCloudAvailable ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(libraryService.iCloudAvailable ? "iCloud Sync" : "Local Only")
                                .font(.caption)
                            Text(syncStatusText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if libraryService.iCloudAvailable {
                            Button(action: { libraryService.forceSync() }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Force Sync")
                        }
                    }
                    .padding(.vertical, 4)
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
                // Show library items for selected collection or recent files
                if collection == "Recent" {
                    RecentFilesGridView(appState: appState)
                } else if collection == "Shared" {
                    SharedLinksGridView(appState: appState)
                } else {
                    LibraryGridView(collection: collection, libraryService: libraryService, appState: appState)
                }
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
                onCreate: { description, isPublic, password in
                    createNewProject(description: description, isPublic: isPublic, password: password)
                },
                onCancel: {
                    newProjectName = ""
                    showNewProjectSheet = false
                }
            )
        }
        .sheet(isPresented: $showEditProjectSheet) {
            EditProjectSheet(
                projectName: $editProjectName,
                projectDescription: $editProjectDescription,
                isPublic: $editProjectIsPublic,
                password: $editProjectPassword,
                isSaving: $isSavingProject,
                onSave: saveProjectEdits,
                onCancel: {
                    showEditProjectSheet = false
                    resetEditProjectState()
                }
            )
        }
        .alert("Delete Project?", isPresented: $showDeleteProjectConfirm) {
            Button("Cancel", role: .cancel) {
                projectToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    deleteProject(project)
                }
                projectToDelete = nil
            }
        } message: {
            Text("This will delete the project '\(projectToDelete ?? "")' and remove items from this collection. This action cannot be undone.")
        }
        .onDrop(of: [.fileURL, .image, .movie, .audio, .pdf, .plainText, .data, .item], isTargeted: nil) { providers in
            handleFileDrop(providers)
            return true
        }
    }

    // MARK: - File Drop Handling

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // Handle file URLs
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url, error == nil else { return }
                    Task { @MainActor in
                        await processDroppedFile(url)
                    }
                }
            }
            // Handle images directly
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, error in
                    guard let image = image as? NSImage, error == nil else { return }
                    Task { @MainActor in
                        appState.currentImage = image
                        appState.annotations = []
                        openWindow(id: "editor", value: UUID())
                    }
                }
            }
        }
    }

    private func processDroppedFile(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        print("📁 MainWindow drop: \(url.lastPathComponent) (ext: \(ext))")

        // Image files - open in editor
        if ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp", "heic"].contains(ext) {
            if let image = NSImage(contentsOf: url) {
                appState.currentImage = image
                appState.annotations = []
                openWindow(id: "editor", value: UUID())
            }
            return
        }

        // Video/Audio files - save to library and share
        if ["mp4", "mov", "m4v", "avi", "mp3", "wav", "m4a", "aac"].contains(ext) {
            do {
                let itemType: LibraryItem.ItemType = ["mp3", "wav", "m4a", "aac"].contains(ext) ? .voiceRecording : .recording
                let item = try libraryService.saveRecording(from: url, type: itemType, name: url.deletingPathExtension().lastPathComponent, collection: selectedCollection ?? "Screenshots")
                print("✅ Saved dropped file to library: \(item.name)")
                await showSharePrompt(for: url, title: item.name)
            } catch {
                print("❌ Failed to save dropped file: \(error)")
            }
            return
        }

        // All other files (pdf, md, txt, zip, etc.) - upload directly
        print("📤 Uploading file: \(url.lastPathComponent)")
        await showSharePrompt(for: url, title: url.deletingPathExtension().lastPathComponent)
    }

    private func showSharePrompt(for url: URL, title: String) async {
        do {
            let shareURL = try await ShareService.shared.uploadFileAndGetShareableLink(
                fileURL: url,
                title: title,
                isPublic: true
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)

            await NotificationHelper.showNotification(
                title: "File Shared!",
                body: "Link copied to clipboard: \(title)"
            )
            print("✅ File shared: \(shareURL)")
        } catch {
            print("❌ Failed to share file: \(error)")
        }
    }

    // MARK: - Project Management

    private func createNewProject(description: String?, isPublic: Bool, password: String?) {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        libraryService.addCollection(name)
        newProjectName = ""
        showNewProjectSheet = false
        selectedCollection = name

        // Save collection to CloudKit if public
        if isPublic {
            Task {
                do {
                    try await ShareService.shared.saveCollection(
                        name: name,
                        description: description,
                        isPublic: isPublic,
                        password: password
                    )
                    print("✅ Collection saved to CloudKit: \(name)")
                } catch {
                    print("❌ Failed to save collection to CloudKit: \(error)")
                }
            }
        }
    }

    private func deleteProject(_ name: String) {
        libraryService.removeCollection(name)
        if selectedCollection == name {
            selectedCollection = nil
        }
    }

    private func saveProjectEdits() {
        guard let originalName = editingProject else { return }
        isSavingProject = true

        Task {
            do {
                // Rename locally if name changed
                if editProjectName != originalName {
                    libraryService.renameCollection(originalName, to: editProjectName)
                    if selectedCollection == originalName {
                        selectedCollection = editProjectName
                    }
                }

                // Save to CloudKit
                try await ShareService.shared.saveCollection(
                    name: editProjectName,
                    description: editProjectDescription.isEmpty ? nil : editProjectDescription,
                    isPublic: editProjectIsPublic,
                    password: editProjectPassword.isEmpty ? nil : editProjectPassword
                )

                await MainActor.run {
                    isSavingProject = false
                    showEditProjectSheet = false
                    resetEditProjectState()
                }
            } catch {
                await MainActor.run {
                    isSavingProject = false
                }
            }
        }
    }

    private func resetEditProjectState() {
        editingProject = nil
        editProjectName = ""
        editProjectDescription = ""
        editProjectIsPublic = false
        editProjectPassword = ""
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
    var forceGif: Bool = false
    var withWebcam: Bool = false

    @StateObject private var recordingService = ScreenRecordingService.shared

    private var isThisModeRecording: Bool {
        recordingService.state.isRecording && 
        recordingService.configuration.captureMode == mode &&
        (forceGif ? recordingService.configuration.outputFormat == .gif : true) &&
        (withWebcam ? recordingService.configuration.enableWebcam : true)
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
                do {
                    let url = try await recordingService.stopRecording()
                    // Save to library and show
                    await MainActor.run {
                        showRecordingResult(url: url)
                    }
                } catch {
                    print("❌ Failed to stop recording: \(error)")
                }
            }
        } else {
            // Start recording
            startRecording()
        }
    }

    private func startRecording() {
        recordingService.configuration.captureMode = mode
        
        // Force GIF format if this is the GIF button
        if forceGif {
            recordingService.configuration.outputFormat = .gif
        }
        
        // Enable webcam if this is the webcam button
        if withWebcam {
            recordingService.configuration.enableWebcam = true
            // Check camera permission
            Task {
                let hasPermission = await CameraPermission.checkAndRequest()
                if !hasPermission {
                    print("❌ Camera permission denied")
                    return
                }
                // Continue with recording after permission granted
                await MainActor.run {
                    continueStartRecording()
                }
            }
            return
        }

        continueStartRecording()
    }
    
    private func continueStartRecording() {
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
    
    private func showRecordingResult(url: URL) {
        do {
            // Determine the type from file extension
            let ext = url.pathExtension.lowercased()
            let itemType: LibraryItem.ItemType
            switch ext {
            case "gif":
                itemType = .gif
            case "m4a":
                itemType = .voiceRecording
            default:
                itemType = .recording
            }
            
            // Save to library
            let fileName = url.lastPathComponent
            let name = fileName.replacingOccurrences(of: ".\(ext)", with: "")
            let item = try LibraryService.shared.saveRecording(from: url, type: itemType, name: name, collection: "Recordings")
            
            // Show notification that it was saved
            Task {
                await NotificationHelper.showNotification(title: "Recording Saved", body: "'\(name)' was saved to your library")
            }
            
            // Open the file in default app (QuickTime for videos, Preview for GIFs)
            NSWorkspace.shared.open(url)
            
            print("✅ Recording saved to library: \(item.name)")
        } catch {
            print("❌ Failed to save recording to library: \(error)")
            // Still try to open the file
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Main Window New Project Sheet
struct MainWindowNewProjectSheet: View {
    @Binding var projectName: String
    let onCreate: (String?, Bool, String?) -> Void  // (description, isPublic, password)
    let onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    @State private var projectDescription = ""
    @State private var isPublic = false
    @State private var usePassword = false
    @State private var password = ""
    @State private var isSaving = false
    @AppStorage("defaultSharePublic") private var defaultSharePublic = false

    var body: some View {
        VStack(spacing: 16) {
            Text("New Collection")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Collection name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("What's this collection for?", text: $projectDescription)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Toggle("Make public (shareable link)", isOn: $isPublic)

                if isPublic {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Password protect", isOn: $usePassword)

                        if usePassword {
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.leading, 20)

                    Text("Public collections can be shared via link")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    onCreate(
                        projectDescription.isEmpty ? nil : projectDescription,
                        isPublic,
                        usePassword && !password.isEmpty ? password : nil
                    )
                }) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Create")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            isNameFocused = true
            isPublic = defaultSharePublic
        }
    }
}

// MARK: - Edit Project Sheet
struct EditProjectSheet: View {
    @Binding var projectName: String
    @Binding var projectDescription: String
    @Binding var isPublic: Bool
    @Binding var password: String
    @Binding var isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @AppStorage("shareUsername") private var shareUsername = ""
    @State private var usePassword = false
    @State private var removePassword = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Collection")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Collection name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("What's this collection for?", text: $projectDescription)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Toggle("Make public (shareable link)", isOn: $isPublic)

                if isPublic {
                    if !shareUsername.isEmpty {
                        Text("Share URL: ?user=\(shareUsername)&collection=\(projectName.replacingOccurrences(of: " ", with: "_").lowercased())")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Password protect", isOn: $usePassword)

                        if usePassword {
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.leading, 20)
                }
            }

            HStack {
                Spacer()
                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectName.isEmpty || isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
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

// MARK: - Recent Files Grid View
struct RecentFilesGridView: View {
    @ObservedObject var appState: AppState

    @State private var recentFiles: [URL] = []
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var selectedFiles: Set<URL> = []
    @State private var isSelectionMode = false

    enum ViewMode {
        case grid, list
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    private var filteredFiles: [URL] {
        var files = recentFiles
        if !searchText.isEmpty {
            files = files.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
        }
        return files.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with search and view mode
            HStack(spacing: 12) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search recent files...", text: $searchText)
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
                .frame(maxWidth: 300)

                Spacer()

                // Selection mode toggle
                if !filteredFiles.isEmpty {
                    Button {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedFiles.removeAll()
                        }
                    } label: {
                        Label(isSelectionMode ? "Done" : "Select", systemImage: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                // View mode toggle
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Bulk actions bar (when in selection mode with items selected)
            if isSelectionMode && !selectedFiles.isEmpty {
                HStack(spacing: 16) {
                    Text("\(selectedFiles.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: deleteSelectedFiles) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button(action: { selectedFiles.removeAll() }) {
                        Label("Deselect All", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
            }

            Divider()

            if filteredFiles.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Recent Files")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Recent recordings and captures will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == .grid {
                // Grid of files
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredFiles, id: \.self) { fileURL in
                            RecentFileCard(
                                fileURL: fileURL,
                                appState: appState,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedFiles.contains(fileURL),
                                onToggleSelection: { toggleSelection(fileURL) }
                            )
                        }
                    }
                    .padding(16)
                }
            } else {
                // List view
                List(filteredFiles, id: \.self, selection: isSelectionMode ? $selectedFiles : nil) { fileURL in
                    RecentFileListRow(
                        fileURL: fileURL,
                        appState: appState,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedFiles.contains(fileURL),
                        onToggleSelection: { toggleSelection(fileURL) }
                    )
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            loadRecentFiles()
        }
        .refreshable {
            loadRecentFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newRecordingAvailable)) { _ in
            // Refresh recent files when new recording is available
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                loadRecentFiles()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingSaved)) { _ in
            // Refresh recent files when recording is saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                loadRecentFiles()
            }
        }
    }

    private func toggleSelection(_ url: URL) {
        if selectedFiles.contains(url) {
            selectedFiles.remove(url)
        } else {
            selectedFiles.insert(url)
        }
    }

    private func deleteSelectedFiles() {
        for url in selectedFiles {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFiles.removeAll()
        loadRecentFiles()
    }
    
    private func loadRecentFiles() {
        // Use app's container temp directory instead of system temp directory
        let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("tmp")
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        
        // Try multiple potential directories where Instinctly files might be
        let possibleDirs = [
            containerURL,
            FileManager.default.temporaryDirectory,
            downloadsURL,
            desktopURL
        ].compactMap { $0 }
        
        var foundFiles: [URL] = []
        
        for dir in possibleDirs {
            print("🔍 Checking directory: \(dir.path)")
            
            guard FileManager.default.fileExists(atPath: dir.path) else {
                print("📁 Directory doesn't exist: \(dir.path)")
                continue
            }
            
            do {
                let allFiles = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                
                // Filter for media files
                let mediaFiles = allFiles.filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ["gif", "mp4", "mov", "webm", "m4a", "png", "jpg", "jpeg"].contains(ext)
                }.filter { url in
                    let fileName = url.lastPathComponent
                    // Include files that contain "Instinctly" or "voice_" (for voice recordings)
                    return fileName.contains("Instinctly") || fileName.hasPrefix("voice_")
                }
                
                foundFiles.append(contentsOf: mediaFiles)
                print("📄 Found \(mediaFiles.count) files in \(dir.path)")
                
                // Don't break - collect from all directories
            } catch {
                print("❌ Failed to read directory \(dir.path): \(error)")
                continue
            }
        }
        
        // Sort by modification date (newest first)
        recentFiles = foundFiles.sorted { url1, url2 in
            let date1 = (try? FileManager.default.attributesOfItem(atPath: url1.path))?[.modificationDate] as? Date ?? Date.distantPast
            let date2 = (try? FileManager.default.attributesOfItem(atPath: url2.path))?[.modificationDate] as? Date ?? Date.distantPast
            return date1 > date2
        }
        
        print("✅ Loaded \(recentFiles.count) recent files total")
    }
}

// MARK: - Shared Links Grid View
struct SharedLinksGridView: View {
    @ObservedObject var appState: AppState

    @State private var sharedItems: [(recordID: String, title: String, fileName: String, mediaType: String, createdAt: Date, collection: String?, viewCount: Int, hasPassword: Bool)] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var isUploading = false
    @State private var uploadProgress: String = ""
    @State private var isDragging = false
    @State private var showUploadSheet = false
    @State private var pendingUploadURLs: [URL] = []
    @State private var uploadPassword: String = ""
    @State private var uploadCollection: String = ""
    @StateObject private var shareService = ShareService.shared
    @StateObject private var libraryService = LibraryService.shared

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)]

    private var filteredItems: [(recordID: String, title: String, fileName: String, mediaType: String, createdAt: Date, collection: String?, viewCount: Int, hasPassword: Bool)] {
        if searchText.isEmpty {
            return sharedItems
        }
        return sharedItems.filter { $0.fileName.localizedCaseInsensitiveContains(searchText) }
    }

    // Supported file types for upload
    private let supportedTypes: [String] = ["png", "jpg", "jpeg", "gif", "mp4", "mov", "webm", "m4a", "wav", "pdf", "md", "txt"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Shared Links")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isUploading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(uploadProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                // View mode toggle
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .help("Toggle view mode")

                // Add file button
                Button(action: openFilePicker) {
                    Image(systemName: "plus")
                }
                .help("Add files to share")
                .disabled(isUploading)

                Button(action: loadSharedItems) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(16)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search shared files...", text: $searchText)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Content
            if filteredItems.isEmpty && !isDragging {
                // Empty state with drop zone
                ZStack {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "link.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(isLoading ? "Loading..." : "No Shared Links")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Drop files here or click + to upload and share")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !isLoading {
                            HStack(spacing: 12) {
                                Button("Add Files") {
                                    openFilePicker()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isUploading)

                                Button("Load Shared Files") {
                                    loadSharedItems()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Content area with items
                ScrollView {
                    if viewMode == .grid {
                        // Grid view
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filteredItems, id: \.recordID) { item in
                                SharedLinkCard(item: item, onDelete: { deleteItem(item.recordID) })
                            }
                        }
                        .padding(16)
                    } else {
                        // List view
                        LazyVStack(spacing: 8) {
                            ForEach(filteredItems, id: \.recordID) { item in
                                SharedLinkListRow(item: item, onDelete: { deleteItem(item.recordID) })
                            }
                        }
                        .padding(16)
                    }
                }
            }

            // Drag overlay
            if isDragging {
                ZStack {
                    Color.accentColor.opacity(0.1)

                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Text("Drop files to upload and share")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .padding(8)
                )
            }
        }
        .onAppear {
            if sharedItems.isEmpty {
                loadSharedItems()
            }
        }
        .refreshable {
            loadSharedItems()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
            return true
        }
        .sheet(isPresented: $showUploadSheet) {
            UploadShareSheet(
                urls: pendingUploadURLs,
                password: $uploadPassword,
                collection: $uploadCollection,
                collections: libraryService.collections,
                onUpload: { password, collection in
                    showUploadSheet = false
                    uploadFilesWithOptions(urls: pendingUploadURLs, password: password, collection: collection)
                    pendingUploadURLs = []
                    uploadPassword = ""
                    uploadCollection = ""
                },
                onCancel: {
                    showUploadSheet = false
                    pendingUploadURLs = []
                    uploadPassword = ""
                    uploadCollection = ""
                }
            )
        }
    }

    // MARK: - File Upload

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .png, .jpeg, .gif,
            .mpeg4Movie, .quickTimeMovie,
            .audio,
            .pdf, .plainText
        ]
        panel.message = "Select files to upload and share"

        if panel.runModal() == .OK {
            pendingUploadURLs = panel.urls
            showUploadSheet = true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var droppedURLs: [URL] = []

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                defer { group.leave() }
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else {
                    return
                }

                // Check if file type is supported
                let ext = url.pathExtension.lowercased()
                if supportedTypes.contains(ext) {
                    droppedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if !droppedURLs.isEmpty {
                pendingUploadURLs = droppedURLs
                showUploadSheet = true
            }
        }
    }

    private func uploadFilesWithOptions(urls: [URL], password: String?, collection: String?) {
        guard !urls.isEmpty else { return }

        isUploading = true
        uploadProgress = "Uploading \(urls.count) file(s)..."

        Task {
            var successCount = 0
            var failCount = 0

            for (index, url) in urls.enumerated() {
                await MainActor.run {
                    uploadProgress = "Uploading \(index + 1) of \(urls.count)..."
                }

                do {
                    _ = try await shareService.uploadFileAndGetShareableLink(
                        fileURL: url,
                        collection: collection?.isEmpty == false ? collection : nil,
                        password: password?.isEmpty == false ? password : nil
                    )
                    successCount += 1
                } catch {
                    failCount += 1
                    print("❌ Failed to upload \(url.lastPathComponent): \(error)")
                }
            }

            await MainActor.run {
                isUploading = false
                uploadProgress = ""

                // Show notification
                if successCount > 0 {
                    Task {
                        await NotificationHelper.showNotification(
                            title: "Files Uploaded",
                            body: "\(successCount) file(s) uploaded successfully\(failCount > 0 ? ", \(failCount) failed" : "")"
                        )
                    }
                }

                // Reload the list
                loadSharedItems()
            }
        }
    }
    
    private func loadSharedItems() {
        isLoading = true
        Task {
            do {
                let items = try await ShareService.shared.fetchAllSharedMedia()
                await MainActor.run {
                    sharedItems = items
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to load shared items: \(error)")
                    isLoading = false
                }
            }
        }
    }

    private func deleteItem(_ recordID: String) {
        Task {
            do {
                try await ShareService.shared.deleteSharedMedia(recordID: recordID)
                await MainActor.run {
                    sharedItems.removeAll { $0.recordID == recordID }
                    print("✅ Deleted shared item: \(recordID)")
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to delete shared item: \(error)")
                }
            }
        }
    }
}

// MARK: - Upload Share Sheet
struct UploadShareSheet: View {
    let urls: [URL]
    @Binding var password: String
    @Binding var collection: String
    let collections: [String]
    let onUpload: (String?, String?) -> Void
    let onCancel: () -> Void

    @State private var usePassword = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Upload & Share")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }

            // Files to upload
            VStack(alignment: .leading, spacing: 8) {
                Text("Files to share:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(urls, id: \.self) { url in
                            HStack(spacing: 8) {
                                Image(systemName: iconForFile(url))
                                    .foregroundColor(.blue)
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 100)
            }

            Divider()

            // Collection picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Add to collection (optional):")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Collection", selection: $collection) {
                    Text("None").tag("")
                    ForEach(collections, id: \.self) { coll in
                        Text(coll).tag(coll)
                    }
                }
                .pickerStyle(.menu)
            }

            // Password protection
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Password protect", isOn: $usePassword)

                if usePassword {
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    Text("Recipients will need this password to view the file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Upload button
            HStack {
                Spacer()
                Button("Upload \(urls.count) file(s)") {
                    onUpload(usePassword ? password : nil, collection.isEmpty ? nil : collection)
                }
                .buttonStyle(.borderedProminent)
                .disabled(usePassword && password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 400)
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg": return "photo"
        case "gif": return "photo.stack"
        case "mp4", "mov", "webm": return "video.fill"
        case "m4a", "wav": return "waveform"
        case "pdf": return "doc.fill"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Recent File Share Sheet
struct RecentFileShareSheet: View {
    let fileURL: URL
    @Binding var usePassword: Bool
    @Binding var password: String
    @Binding var sharedURL: URL?
    @Binding var showLinkCopied: Bool
    @Binding var isPresented: Bool
    @ObservedObject var shareService: ShareService

    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var shareTitle: String = ""
    @State private var shareDescription: String = ""
    @State private var isPublic: Bool = false
    @AppStorage("defaultSharePublic") private var defaultSharePublic = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(sharedURL != nil ? "Link Ready!" : "Share File")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            if let shareURL = sharedURL {
                // Success state - show link
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("Link copied to clipboard!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Show URL
                    HStack {
                        Text(shareURL.absoluteString)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                    HStack(spacing: 12) {
                        if usePassword {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.orange)
                                Text("Protected")
                                    .font(.caption)
                            }
                        }
                        if isPublic {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .foregroundColor(.blue)
                                Text("Public")
                                    .font(.caption)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.gray)
                                Text("Private")
                                    .font(.caption)
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                // Upload state
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // File info
                        HStack(spacing: 12) {
                            Image(systemName: iconForFile(fileURL))
                                .font(.system(size: 24))
                                .foregroundColor(.blue)

                            VStack(alignment: .leading) {
                                Text(fileURL.lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(fileType(for: fileURL))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                        // Title field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Enter a title", text: $shareTitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Description field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Add a description", text: $shareDescription)
                                .textFieldStyle(.roundedBorder)
                        }

                        Divider()

                        // Visibility toggle
                        Toggle("Make public (visible on profile)", isOn: $isPublic)

                        // Password toggle
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Password protect", isOn: $usePassword)

                            if usePassword {
                                SecureField("Enter password", text: $password)
                                    .textFieldStyle(.roundedBorder)

                                Text("Recipients will need this password to view")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Upload button
                HStack {
                    Spacer()
                    Button(action: uploadAndShare) {
                        if isUploading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                            Text("Uploading...")
                        } else {
                            Image(systemName: "link.badge.plus")
                            Text("Create Link")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploading || (usePassword && password.isEmpty))
                }
            }
        }
        .padding(24)
        .frame(width: 400, height: sharedURL != nil ? 300 : 450)
        .onAppear {
            isPublic = defaultSharePublic
        }
    }

    private func uploadAndShare() {
        isUploading = true
        errorMessage = nil

        Task {
            do {
                let url = try await shareService.uploadFileAndGetShareableLink(
                    fileURL: fileURL,
                    title: shareTitle.isEmpty ? nil : shareTitle,
                    description: shareDescription.isEmpty ? nil : shareDescription,
                    password: usePassword ? password : nil,
                    isPublic: isPublic
                )

                await MainActor.run {
                    sharedURL = url
                    showLinkCopied = true

                    // Copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)

                    print("✅ Link copied to clipboard: \(url.absoluteString)")

                    // Reset copied indicator after a few seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showLinkCopied = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg": return "photo"
        case "gif": return "photo.stack"
        case "mp4", "mov", "webm": return "video.fill"
        case "m4a", "wav": return "waveform"
        default: return "doc"
        }
    }

    private func fileType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg": return "Image"
        case "gif": return "GIF"
        case "mp4", "mov", "webm": return "Video"
        case "m4a", "wav": return "Audio"
        default: return "File"
        }
    }
}

// MARK: - Shared Link List Row (for list view)
struct SharedLinkListRow: View {
    let item: (recordID: String, title: String, fileName: String, mediaType: String, createdAt: Date, collection: String?, viewCount: Int, hasPassword: Bool)
    let onDelete: () -> Void

    @State private var isHovered = false

    private var shareURL: String {
        "https://daniellauding.github.io/instinctly-share?id=\(item.recordID)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Media type icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(mediaTypeColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: mediaTypeIcon)
                    .font(.system(size: 18))
                    .foregroundColor(mediaTypeColor)

                // Password indicator badge
                if item.hasPassword {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                    }
                    .frame(width: 44, height: 44)
                }
            }

            // File info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if item.hasPassword {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.mediaType.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let collection = item.collection {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(collection)
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }

                    // View count
                    HStack(spacing: 2) {
                        Image(systemName: "eye")
                            .font(.caption2)
                        Text("\(item.viewCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(formatDate(item.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions (always visible in list view)
            HStack(spacing: 8) {
                Button(action: copyLink) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Link")

                Button(action: openLink) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Browser")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete from iCloud")
            }
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Link") { copyLink() }
            Button("Open in Browser") { openLink() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var mediaTypeIcon: String {
        switch item.mediaType {
        case "gif": return "photo.stack"
        case "video": return "video.fill"
        case "audio": return "waveform"
        case "pdf": return "doc.fill"
        case "text": return "doc.text"
        default: return "photo"
        }
    }

    private var mediaTypeColor: Color {
        switch item.mediaType {
        case "gif": return .orange
        case "video": return .blue
        case "audio": return .green
        case "pdf": return .red
        case "text": return .purple
        default: return .gray
        }
    }

    private func copyLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareURL, forType: .string)
        print("📋 Copied link: \(shareURL)")
    }

    private func openLink() {
        if let url = URL(string: shareURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Shared Link Card
struct SharedLinkCard: View {
    let item: (recordID: String, title: String, fileName: String, mediaType: String, createdAt: Date, collection: String?, viewCount: Int, hasPassword: Bool)
    let onDelete: () -> Void

    @State private var isHovered = false

    private var shareURL: String {
        "https://daniellauding.github.io/instinctly-share?id=\(item.recordID)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Media type icon and controls
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 8) {
                            ZStack {
                                Image(systemName: mediaTypeIcon)
                                    .font(.system(size: 32))
                                    .foregroundColor(mediaTypeColor)

                                // Password badge
                                if item.hasPassword {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white)
                                                .padding(4)
                                                .background(Color.orange)
                                                .clipShape(Circle())
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .offset(x: 10, y: 10)
                                }
                            }

                            Text(item.mediaType.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                // View count badge (top left)
                VStack {
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "eye")
                                .font(.caption2)
                            Text("\(item.viewCount)")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(6)

                        Spacer()
                    }
                    Spacer()
                }

                // Controls (show on hover)
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: copyLink) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy Link")

                        Button(action: openLink) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Open in Browser")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete from iCloud")
                    }
                    .padding(8)
                }
            }

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if item.hasPassword {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 4) {
                    if let collection = item.collection {
                        Image(systemName: "folder")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(collection)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("•")
                            .foregroundColor(.secondary)
                    }
                    Text(formatDate(item.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(shareURL)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Link") { copyLink() }
            Button("Open in Browser") { openLink() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var mediaTypeIcon: String {
        switch item.mediaType {
        case "gif": return "photo.stack"
        case "video": return "video.fill"
        case "audio": return "waveform"
        case "pdf": return "doc.fill"
        case "text": return "doc.text"
        default: return "photo"
        }
    }

    private var mediaTypeColor: Color {
        switch item.mediaType {
        case "gif": return .orange
        case "video": return .blue
        case "audio": return .green
        case "pdf": return .red
        case "text": return .purple
        default: return .gray
        }
    }

    private func copyLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareURL, forType: .string)
        print("📋 Copied link: \(shareURL)")
    }

    private func openLink() {
        if let url = URL(string: shareURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Recent File List Row
struct RecentFileListRow: View {
    let fileURL: URL
    @ObservedObject var appState: AppState
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?

    @State private var thumbnail: NSImage?
    @State private var fileSize: String = ""
    @State private var showEditSheet = false
    @StateObject private var shareService = ShareService.shared

    private var fileType: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "gif": return "GIF"
        case "mp4", "mov", "webm": return "Video"
        case "m4a": return "Audio"
        case "png", "jpg", "jpeg": return "Image"
        default: return "File"
        }
    }

    private var iconName: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "gif": return "photo.stack"
        case "mp4", "mov", "webm": return "video.fill"
        case "m4a": return "waveform"
        case "png", "jpg", "jpeg": return "photo"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "gif": return .orange
        case "mp4", "mov", "webm": return .blue
        case "m4a": return .green
        case "png", "jpg", "jpeg": return .purple
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            if isSelectionMode {
                Button(action: { onToggleSelection?() }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            // Thumbnail
            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 40)
                        .overlay {
                            Image(systemName: iconName)
                                .foregroundColor(iconColor)
                        }
                }
            }

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(fileURL.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(fileType)
                        .font(.caption)
                        .foregroundColor(iconColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(iconColor.opacity(0.1))
                        .cornerRadius(4)

                    Text(fileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatDate())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            if !isSelectionMode {
                HStack(spacing: 8) {
                    if isEditableFormat {
                        Button(action: { showEditSheet = true }) {
                            Image(systemName: "scissors")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit Clip")
                    }
                    
                    Button(action: { NSWorkspace.shared.open(fileURL) }) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open")

                    Button(action: { NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "") }) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")

                    Button(action: deleteFile) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection?()
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        }
        .onAppear {
            loadThumbnail()
            loadFileSize()
        }
        .contextMenu {
            if isEditableFormat {
                Button {
                    showEditSheet = true
                } label: {
                    Label("Edit Clip...", systemImage: "scissors")
                }
                
                Divider()
            }
            
            Button {
                NSWorkspace.shared.open(fileURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            
            Button {
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            
            Divider()
            
            Button(role: .destructive) {
                deleteFile()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ClipEditorView(
                fileURL: fileURL,
                onSave: { editedURL in
                    showEditSheet = false
                },
                onCancel: {
                    showEditSheet = false
                }
            )
        }
    }
    
    private var isEditableFormat: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ["mp4", "mov", "gif", "m4a"].contains(ext)
    }

    private func formatDate() -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let date = attrs[.modificationDate] as? Date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            let nsImage = NSImage(contentsOf: fileURL)
            DispatchQueue.main.async {
                thumbnail = nsImage
            }
        }
    }

    private func loadFileSize() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else { return }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        fileSize = formatter.string(fromByteCount: size)
    }

    private func deleteFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Recent File Card
struct RecentFileCard: View {
    let fileURL: URL
    @ObservedObject var appState: AppState
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?

    @State private var isHovered = false
    @State private var fileSize: String = ""
    @State private var thumbnail: NSImage?
    @State private var showPreview = false
    @State private var showShareSheet = false
    @State private var showUnifiedShareSheet = false
    @State private var sharePassword = ""
    @State private var usePassword = false
    @State private var sharedURL: URL?
    @State private var showLinkCopied = false
    @State private var showEditSheet = false
    @StateObject private var shareService = ShareService.shared

    private var fileType: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "gif": return "GIF"
        case "mp4", "mov", "webm": return "Video"
        case "m4a": return "Audio"
        case "png", "jpg", "jpeg": return "Image"
        default: return "File"
        }
    }
    
    private var iconName: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "gif": return "photo.stack"
        case "mp4", "mov", "webm": return "video.fill"
        case "m4a": return "waveform"
        case "png", "jpg", "jpeg": return "photo"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "gif": return .orange
        case "mp4", "mov", "webm": return .blue
        case "m4a": return .green
        case "png", "jpg", "jpeg": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File thumbnail or icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(16/10, contentMode: .fit)

                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            // File type badge
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text(fileType)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(iconColor.opacity(0.8))
                                        .cornerRadius(4)
                                        .padding(4)
                                }
                            }
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: iconName)
                            .font(.system(size: 32))
                            .foregroundColor(iconColor)

                        Text(fileType)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }

                // Selection overlay
                if isSelectionMode {
                    Color.black.opacity(isSelected ? 0.3 : 0.1)
                        .cornerRadius(8)

                    VStack {
                        HStack {
                            Button(action: { onToggleSelection?() }) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(isSelected ? .accentColor : .white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                } else if isHovered {
                    Color.black.opacity(0.4)
                        .cornerRadius(8)
                    
                    VStack(spacing: 8) {
                        // Open button
                        Button(action: openFile) {
                            Label("Open", systemImage: "arrow.up.right.square")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 8) {
                            // Edit button for editable formats
                            if isEditableFormat {
                                Button(action: { showEditSheet = true }) {
                                    Image(systemName: "scissors")
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Edit Clip")
                            }
                            
                            // Share to iCloud
                            Button(action: { showShareSheet = true }) {
                                if shareService.isSharing {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                } else if showLinkCopied {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "link.badge.plus")
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(shareService.isSharing)

                            // Copy to clipboard
                            Button(action: copyPath) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            
                            // Show in Finder
                            Button(action: showInFinder) {
                                Image(systemName: "folder")
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            
                            // Save to Library
                            Button(action: saveToLibrary) {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundColor(.blue)
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
            .onTapGesture {
                showPreview = true
            }
            .onTapGesture(count: 2) {
                openFile()
            }
            .contextMenu {
                if isEditableFormat {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Clip...", systemImage: "scissors")
                    }
                    
                    Divider()
                }
                
                Button {
                    openFile()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                
                Button {
                    showUnifiedShareSheet = true
                } label: {
                    Label("Share to Cloud...", systemImage: "icloud.and.arrow.up")
                }
                
                Button {
                    copyPath()
                } label: {
                    Label("Copy Path", systemImage: "doc.on.clipboard")
                }
                
                Button {
                    showInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                
                Button {
                    saveToLibrary()
                } label: {
                    Label("Save to Library", systemImage: "square.and.arrow.down")
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    Text(fileSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatDate())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            loadFileSize()
            loadThumbnail()
        }
        .sheet(isPresented: $showPreview) {
            FilePreviewPanel(fileURL: fileURL, isPresented: $showPreview)
        }
        .sheet(isPresented: $showShareSheet) {
            RecentFileShareSheet(
                fileURL: fileURL,
                usePassword: $usePassword,
                password: $sharePassword,
                sharedURL: $sharedURL,
                showLinkCopied: $showLinkCopied,
                isPresented: $showShareSheet,
                shareService: shareService
            )
        }
        .sheet(isPresented: $showUnifiedShareSheet) {
            UnifiedShareView(
                fileURL: fileURL,
                title: fileURL.deletingPathExtension().lastPathComponent,
                initialDescription: nil,
                isPresented: $showUnifiedShareSheet
            )
        }
        .sheet(isPresented: $showEditSheet) {
            ClipEditorView(
                fileURL: fileURL,
                onSave: { editedURL in
                    showEditSheet = false
                },
                onCancel: {
                    showEditSheet = false
                }
            )
        }
    }
    
    private var isEditableFormat: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ["mp4", "mov", "gif", "m4a"].contains(ext)
    }

    private func openFile() {
        NSWorkspace.shared.open(fileURL)
    }
    
    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL.path, forType: .string)
    }
    
    private func showInFinder() {
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }
    
    private func saveToLibrary() {
        do {
            let ext = fileURL.pathExtension.lowercased()
            let itemType: LibraryItem.ItemType
            switch ext {
            case "gif":
                itemType = .gif
            case "m4a":
                itemType = .voiceRecording
            case "mp4", "mov", "webm":
                itemType = .recording
            default:
                itemType = .screenshot
            }
            
            let fileName = fileURL.lastPathComponent
            let name = fileName.replacingOccurrences(of: ".\(ext)", with: "")
            _ = try LibraryService.shared.saveRecording(from: fileURL, type: itemType, name: name, collection: "Recordings")
            
            // Show notification
            Task {
                await NotificationHelper.showNotification(title: "Saved to Library", body: "'\(name)' was added to your library")
            }
            
            print("✅ Saved to library: \(name)")
        } catch {
            print("❌ Failed to save to library: \(error)")
        }
    }
    
    private func loadFileSize() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSize = formatter.string(fromByteCount: size)
            }
        } catch {
            fileSize = "—"
        }
    }
    
    private func formatDate() -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let date = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
        } catch {}
        return "—"
    }
    
    private func loadThumbnail() {
        Task {
            let thumb = await generateThumbnail(for: fileURL)
            await MainActor.run {
                thumbnail = thumb
            }
        }
    }
    
    private func generateThumbnail(for url: URL) async -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "png", "jpg", "jpeg", "gif":
            // For images and GIFs, load directly
            return NSImage(contentsOf: url)
            
        case "mp4", "mov", "webm":
            // For videos, generate thumbnail from first frame
            return await generateVideoThumbnail(for: url)
            
        case "m4a":
            // For audio, return nil to show icon
            return nil
            
        default:
            return nil
        }
    }
    
    private func generateVideoThumbnail(for url: URL) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 200)
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 1000)
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let cgImage = cgImage {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    continuation.resume(returning: nsImage)
                } else {
                    continuation.resume(returning: nil)
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
    @State private var showPreview = false
    @StateObject private var shareService = ShareService.shared

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
                        .overlay(
                            // File type badge for library items too
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text(item.type.rawValue.uppercased())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(badgeColor.opacity(0.8))
                                        .cornerRadius(4)
                                        .padding(4)
                                }
                            }
                        )
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
                            // Share to iCloud
                            Button(action: shareToCloud) {
                                if shareService.isSharing {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "link.badge.plus")
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(shareService.isSharing)
                            
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
            .onTapGesture {
                showPreview = true
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
        .sheet(isPresented: $showPreview) {
            let url = libraryService.fileURL(for: item)
            FilePreviewPanel(fileURL: url, isPresented: $showPreview)
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
    
    private var badgeColor: Color {
        switch item.type {
        case .screenshot: return .purple
        case .recording: return .blue
        case .gif: return .orange
        case .voiceRecording: return .green
        }
    }

    private var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.createdAt)
    }

    private func loadThumbnail() {
        Task {
            let thumb = await generateLibraryThumbnail(for: item)
            await MainActor.run {
                thumbnail = thumb
            }
        }
    }
    
    private func generateLibraryThumbnail(for item: LibraryItem) async -> NSImage? {
        switch item.type {
        case .screenshot, .gif:
            // For images and GIFs, load directly from library
            return libraryService.loadImage(for: item)
            
        case .recording:
            // For videos, try to load from library and generate thumbnail
            let fileURL = libraryService.fileURL(for: item)
            return await generateVideoThumbnailFromURL(fileURL)
            
        case .voiceRecording:
            // For audio, return nil to show icon
            return nil
        }
    }
    
    private func generateVideoThumbnailFromURL(_ url: URL) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 200)
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 1000)
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let cgImage = cgImage {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    continuation.resume(returning: nsImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func shareToCloud() {
        Task {
            do {
                let url = libraryService.fileURL(for: item)
                let shareURL = try await shareService.uploadFileAndGetShareableLink(fileURL: url)
                await MainActor.run {
                    print("✅ Library item shared to iCloud: \(shareURL.absoluteString)")
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to share library item: \(error.localizedDescription)")
                }
            }
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
