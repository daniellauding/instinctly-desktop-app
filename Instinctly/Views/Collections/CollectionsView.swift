import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var selectedCollection: String? = "All"
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    @State private var customCollections: [String] = []

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
    private let builtInCollections = ["All", "Screenshots", "Favorites"]
    private var allCollections: [String] { builtInCollections + customCollections }
    private let images: [SavedImage] = [] // Will be populated from Core Data

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
                                Button(role: .destructive) {
                                    deleteCollection(collection)
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
                if images.isEmpty {
                    EmptyCollectionView(collectionName: selectedCollection ?? "All")
                } else {
                    if viewMode == .grid {
                        CollectionGridView(images: filteredImages)
                    } else {
                        CollectionListView(images: filteredImages)
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
        .onAppear {
            loadCollections()
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
    }

    private var filteredImages: [SavedImage] {
        images.filter { image in
            if searchText.isEmpty { return true }
            return image.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func iconForCollection(_ name: String) -> String {
        switch name {
        case "All": return "photo.on.rectangle"
        case "Screenshots": return "camera.viewfinder"
        case "Annotations": return "pencil.tip.crop.circle"
        case "Favorites": return "star"
        default: return "folder"
        }
    }

    private func createNewCollection() {
        guard !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customCollections.contains(name) {
            customCollections.append(name)
            saveCollections()
        }
        newCollectionName = ""
        showNewCollectionSheet = false
    }

    private func deleteCollection(_ name: String) {
        customCollections.removeAll { $0 == name }
        saveCollections()
        if selectedCollection == name {
            selectedCollection = "All"
        }
    }

    private func saveCollections() {
        UserDefaults.standard.set(customCollections, forKey: "customCollections")
    }

    private func loadCollections() {
        customCollections = UserDefaults.standard.stringArray(forKey: "customCollections") ?? []
    }

    private func captureNew() {
        NotificationCenter.default.post(name: .captureRegion, object: nil)
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
    let images: [SavedImage]

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(images) { image in
                    ImageThumbnailView(image: image)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Collection List View
struct CollectionListView: View {
    let images: [SavedImage]

    var body: some View {
        List(images) { image in
            ImageListRowView(image: image)
        }
    }
}

// MARK: - Image Thumbnail View
struct ImageThumbnailView: View {
    let image: SavedImage

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/10, contentMode: .fit)

                if let thumbnail = image.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                        .cornerRadius(8)
                }

                if isHovered {
                    Color.black.opacity(0.3)
                        .cornerRadius(8)

                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Image(systemName: "pencil")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button(action: {}) {
                            Image(systemName: "trash")
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
            VStack(alignment: .leading, spacing: 2) {
                Text(image.name)
                    .font(.caption)
                    .lineLimit(1)

                Text(image.dateFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Image List Row View
struct ImageListRowView: View {
    let image: SavedImage

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnail = image.thumbnail {
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
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(image.name)
                    .font(.body)

                Text(image.dateFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Size
            Text(image.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Saved Image Model (Placeholder)
struct SavedImage: Identifiable {
    let id: UUID
    let name: String
    let date: Date
    let thumbnail: NSImage?
    let size: Int64

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - New Project Sheet
struct NewProjectSheet: View {
    @Binding var projectName: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            TextField("Project name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

#Preview {
    CollectionsView()
        .environmentObject(AppState.shared)
        .frame(width: 900, height: 600)
}
