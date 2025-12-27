import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var libraryService = LibraryService.shared
    @StateObject private var shareService = ShareService.shared

    @State private var selectedCollection: String? = "All"
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""

    // Collection management
    @State private var showEditCollectionSheet = false
    @State private var editingCollection: String?
    @State private var editCollectionName = ""
    @State private var editCollectionDescription = ""
    @State private var editCollectionIsPublic = false
    @State private var editCollectionPassword = ""
    @State private var editCollectionRemovePassword = false
    @State private var isSavingCollection = false
    @State private var showDeleteConfirmation = false
    @State private var collectionToDelete: String?

    // Multi-select
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<LibraryItem.ID> = []

    enum ViewMode {
        case grid, list
    }

    enum SortOrder: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case nameAscending = "Name A-Z"
        case nameDescending = "Name Z-A"
    }

    // Built-in collections
    private let builtInCollections = ["All", "Screenshots", "Recordings", "Favorites"]

    // Custom collections from library service (excluding built-in ones)
    private var customCollections: [String] {
        libraryService.collections.filter { !builtInCollections.contains($0) }
    }

    // Items for current collection
    private var currentItems: [LibraryItem] {
        libraryService.items(in: selectedCollection ?? "All")
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar - Collections
            List(selection: $selectedCollection) {
                Section("Library") {
                    ForEach(builtInCollections, id: \.self) { collection in
                        NavigationLink(value: collection) {
                            Label(collection, systemImage: iconForCollection(collection))
                        }
                    }
                }

                if !customCollections.isEmpty {
                    Section("Projects") {
                        ForEach(customCollections, id: \.self) { collection in
                            NavigationLink(value: collection) {
                                Label(collection, systemImage: "folder")
                            }
                            .contextMenu {
                                Button {
                                    editCollection(collection)
                                } label: {
                                    Label("Edit Collection...", systemImage: "pencil")
                                }

                                Button {
                                    shareCollection(collection)
                                } label: {
                                    Label("Share Collection...", systemImage: "square.and.arrow.up")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    collectionToDelete = collection
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(action: { showNewCollectionSheet = true }) {
                        Label("New Project", systemImage: "plus.circle")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            // Main content area
            VStack(spacing: 0) {
                // Toolbar
                CollectionToolbar(
                    searchText: $searchText,
                    viewMode: $viewMode,
                    sortOrder: $sortOrder
                )

                Divider()

                // Content
                if filteredItems.isEmpty {
                    EmptyCollectionView(collectionName: selectedCollection ?? "All")
                } else {
                    if viewMode == .grid {
                        CollectionGridView(items: filteredItems, libraryService: libraryService)
                    } else {
                        CollectionListView(items: filteredItems, libraryService: libraryService)
                    }
                }
            }
        }
        .navigationTitle(selectedCollection ?? "Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: captureNew) {
                    Label("New Capture", systemImage: "camera.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewProjectSheet(
                projectName: $newCollectionName,
                onCreate: createNewCollection,
                onCancel: {
                    newCollectionName = ""
                    showNewCollectionSheet = false
                }
            )
        }
        .sheet(isPresented: $showEditCollectionSheet) {
            EditCollectionSheet(
                collectionName: $editCollectionName,
                collectionDescription: $editCollectionDescription,
                isPublic: $editCollectionIsPublic,
                password: $editCollectionPassword,
                removePassword: $editCollectionRemovePassword,
                isSaving: $isSavingCollection,
                onSave: saveCollectionEdits,
                onCancel: {
                    showEditCollectionSheet = false
                    resetEditState()
                }
            )
        }
        .alert("Delete Collection?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                collectionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                }
                collectionToDelete = nil
            }
        } message: {
            Text("This will delete the collection '\(collectionToDelete ?? "")' and all its items. This action cannot be undone.")
        }
    }

    private var filteredItems: [LibraryItem] {
        var items = currentItems

        // Filter by search text
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Sort items
        switch sortOrder {
        case .dateDescending:
            items.sort { $0.createdAt > $1.createdAt }
        case .dateAscending:
            items.sort { $0.createdAt < $1.createdAt }
        case .nameAscending:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }

        return items
    }

    private func iconForCollection(_ name: String) -> String {
        switch name {
        case "All": return "photo.on.rectangle"
        case "Screenshots": return "camera.viewfinder"
        case "Recordings": return "video"
        case "Favorites": return "star"
        default: return "folder"
        }
    }

    private func createNewCollection() {
        guard !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        libraryService.addCollection(name)
        newCollectionName = ""
        showNewCollectionSheet = false
        selectedCollection = name
    }

    private func deleteCollection(_ name: String) {
        libraryService.removeCollection(name)
        if selectedCollection == name {
            selectedCollection = "All"
        }
    }

    private func editCollection(_ name: String) {
        editingCollection = name
        editCollectionName = name
        editCollectionDescription = "" // TODO: Load from CloudKit if exists
        editCollectionIsPublic = false // TODO: Load from CloudKit if exists
        editCollectionPassword = ""
        editCollectionRemovePassword = false
        showEditCollectionSheet = true
    }

    private func shareCollection(_ name: String) {
        // For now, just open the edit sheet with share options visible
        editCollection(name)
    }

    private func saveCollectionEdits() {
        guard let originalName = editingCollection else { return }
        isSavingCollection = true

        Task {
            do {
                // Rename locally if name changed
                if editCollectionName != originalName {
                    libraryService.renameCollection(originalName, to: editCollectionName)
                    if selectedCollection == originalName {
                        selectedCollection = editCollectionName
                    }
                }

                // Save to CloudKit
                try await shareService.saveCollection(
                    name: editCollectionName,
                    description: editCollectionDescription.isEmpty ? nil : editCollectionDescription,
                    isPublic: editCollectionIsPublic,
                    password: editCollectionRemovePassword ? nil : (editCollectionPassword.isEmpty ? nil : editCollectionPassword)
                )

                await MainActor.run {
                    isSavingCollection = false
                    showEditCollectionSheet = false
                    resetEditState()
                }
            } catch {
                await MainActor.run {
                    isSavingCollection = false
                    // Show error
                }
            }
        }
    }

    private func resetEditState() {
        editingCollection = nil
        editCollectionName = ""
        editCollectionDescription = ""
        editCollectionIsPublic = false
        editCollectionPassword = ""
        editCollectionRemovePassword = false
    }

    private func captureNew() {
        NotificationCenter.default.post(name: .captureRegion, object: nil)
    }
}

// MARK: - Edit Collection Sheet
struct EditCollectionSheet: View {
    @Binding var collectionName: String
    @Binding var collectionDescription: String
    @Binding var isPublic: Bool
    @Binding var password: String
    @Binding var removePassword: Bool
    @Binding var isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @AppStorage("shareUsername") private var shareUsername = ""
    @State private var hasExistingPassword = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Collection")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section {
                    TextField("Collection Name", text: $collectionName)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $collectionDescription)
                            .frame(height: 60)
                            .font(.body)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                    }
                } header: {
                    Text("Details")
                }

                Section {
                    Toggle("Make collection public", isOn: $isPublic)

                    if isPublic && !shareUsername.isEmpty {
                        HStack {
                            Text("Share URL")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("?user=\(shareUsername)&collection=\(collectionName.replacingOccurrences(of: " ", with: "_").lowercased())")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    if !shareUsername.isEmpty && isPublic {
                        VStack(alignment: .leading, spacing: 4) {
                            if hasExistingPassword {
                                Toggle("Remove password protection", isOn: $removePassword)
                            }

                            if !removePassword {
                                SecureField(hasExistingPassword ? "New password (leave empty to keep)" : "Password (optional)", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    if shareUsername.isEmpty {
                        Text("Set a username in Settings → iCloud to enable sharing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 350)

            Divider()

            // Footer
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
                .disabled(collectionName.isEmpty || isSaving)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400)
    }
}

// MARK: - Collection Toolbar
struct CollectionToolbar: View {
    @Binding var searchText: String
    @Binding var viewMode: CollectionsView.ViewMode
    @Binding var sortOrder: CollectionsView.SortOrder

    var body: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
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

            // Sort order
            Menu {
                ForEach(CollectionsView.SortOrder.allCases, id: \.self) { order in
                    Button(action: { sortOrder = order }) {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)

            // View mode toggle
            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(CollectionsView.ViewMode.grid)
                Image(systemName: "list.bullet").tag(CollectionsView.ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Empty Collection View
struct EmptyCollectionView: View {
    let collectionName: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No images in \(collectionName)")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Capture a screenshot or import an image to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: {}) {
                    Label("Capture", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.borderedProminent)

                Button(action: {}) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Collection Grid View
struct CollectionGridView: View {
    let items: [LibraryItem]
    let libraryService: LibraryService

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    LibraryItemThumbnailView(item: item, libraryService: libraryService)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Collection List View
struct CollectionListView: View {
    let items: [LibraryItem]
    let libraryService: LibraryService

    var body: some View {
        List(items) { item in
            LibraryItemListRowView(item: item, libraryService: libraryService)
        }
    }
}

// MARK: - Library Item Thumbnail View
struct LibraryItemThumbnailView: View {
    let item: LibraryItem
    let libraryService: LibraryService

    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var showEditSheet = false
    @State private var showUnifiedShareSheet = false

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
                    // Show icon based on type
                    Image(systemName: iconForType)
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }

                if isHovered {
                    Color.black.opacity(0.3)
                        .cornerRadius(8)

                    HStack(spacing: 8) {
                        // Favorite
                        Button(action: { libraryService.toggleFavorite(item) }) {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .foregroundColor(item.isFavorite ? .yellow : .white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        // Edit (for video/gif/audio)
                        if isEditableFormat {
                            Button(action: { showEditSheet = true }) {
                                Image(systemName: "scissors")
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Open
                        Button(action: { openItem() }) {
                            Image(systemName: "arrow.up.right.square")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        // Delete
                        Button(action: { libraryService.deleteItem(item) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
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
                openItem()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            
            Button {
                libraryService.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Remove from Favorites" : "Add to Favorites", 
                      systemImage: item.isFavorite ? "star.slash" : "star")
            }
            
            Button {
                showUnifiedShareSheet = true
            } label: {
                Label("Share to Cloud...", systemImage: "icloud.and.arrow.up")
            }
            
            Divider()
            
            Button(role: .destructive) {
                libraryService.deleteItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ClipEditorView(
                fileURL: libraryService.fileURL(for: item),
                onSave: { editedURL in
                    showEditSheet = false
                    // The edited file is saved to Downloads, library will detect it
                },
                onCancel: {
                    showEditSheet = false
                }
            )
        }
        .sheet(isPresented: $showUnifiedShareSheet) {
            UnifiedShareView(
                fileURL: libraryService.fileURL(for: item),
                title: item.fileName,
                initialDescription: nil,
                isPresented: $showUnifiedShareSheet
            )
        }
    }
    
    private var isEditableFormat: Bool {
        let ext = libraryService.fileURL(for: item).pathExtension.lowercased()
        return ["mp4", "mov", "gif", "m4a"].contains(ext)
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

    private func openItem() {
        let url = libraryService.fileURL(for: item)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Library Item List Row View
struct LibraryItemListRowView: View {
    let item: LibraryItem
    let libraryService: LibraryService

    @State private var thumbnail: NSImage?
    @State private var showEditSheet = false
    @State private var showUnifiedShareSheet = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
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
                        Image(systemName: iconForType)
                            .foregroundColor(.secondary)
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    Text(item.name)
                        .font(.body)
                }

                Text(dateFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Type badge
            Text(item.type.rawValue.capitalized)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)

            // Actions
            HStack(spacing: 4) {
                Button(action: { libraryService.toggleFavorite(item) }) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .foregroundColor(item.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                
                if isEditableFormat {
                    Button(action: { showEditSheet = true }) {
                        Image(systemName: "scissors")
                    }
                    .buttonStyle(.borderless)
                }

                Button(action: { openItem() }) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)

                Button(action: { libraryService.deleteItem(item) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadThumbnail()
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
                openItem()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            
            Button {
                libraryService.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Remove from Favorites" : "Add to Favorites", 
                      systemImage: item.isFavorite ? "star.slash" : "star")
            }
            
            Button {
                showUnifiedShareSheet = true
            } label: {
                Label("Share to Cloud...", systemImage: "icloud.and.arrow.up")
            }
            
            Divider()
            
            Button(role: .destructive) {
                libraryService.deleteItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ClipEditorView(
                fileURL: libraryService.fileURL(for: item),
                onSave: { editedURL in
                    showEditSheet = false
                },
                onCancel: {
                    showEditSheet = false
                }
            )
        }
        .sheet(isPresented: $showUnifiedShareSheet) {
            UnifiedShareView(
                fileURL: libraryService.fileURL(for: item),
                title: item.fileName,
                initialDescription: nil,
                isPresented: $showUnifiedShareSheet
            )
        }
    }
    
    private var isEditableFormat: Bool {
        let ext = libraryService.fileURL(for: item).pathExtension.lowercased()
        return ["mp4", "mov", "gif", "m4a"].contains(ext)
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

    private func openItem() {
        let url = libraryService.fileURL(for: item)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - New Project Sheet
struct NewProjectSheet: View {
    @Binding var projectName: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            TextField("Project name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .focused($isNameFocused)
                .onSubmit(onCreate)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)

                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            // Focus the text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFocused = true
            }
        }
    }
}

#Preview {
    CollectionsView()
        .environmentObject(AppState.shared)
        .frame(width: 900, height: 600)
}
