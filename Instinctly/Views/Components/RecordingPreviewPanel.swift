import SwiftUI
import AppKit
import AVKit

/// Floating panel that shows recording preview after recording completes
class RecordingPreviewPanelController: NSWindowController {
    static let shared = RecordingPreviewPanelController()
    
    private var hostingController: NSHostingController<RecordingPreviewPanelView>?
    
    private override init(window: NSWindow?) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Recording Preview"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        
        super.init(window: panel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showPreview(fileURL: URL) {
        let view = RecordingPreviewPanelView(fileURL: fileURL) { [weak self] in
            self?.hidePanel()
        }
        
        hostingController = NSHostingController(rootView: view)
        window?.contentView = hostingController?.view
        
        // Position panel at bottom right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = window?.frame.size ?? .zero
            let x = screenFrame.maxX - panelSize.width - 20
            let y = screenFrame.minY + 20
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hidePanel() {
        window?.orderOut(nil)
        hostingController = nil
    }
}

// MARK: - Preview Panel View
struct RecordingPreviewPanelView: View {
    let fileURL: URL
    let onClose: () -> Void
    
    @StateObject private var recordingService = ScreenRecordingService.shared
    @StateObject private var libraryService = LibraryService.shared
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isSaved = false
    @State private var showDeleteAlert = false
    
    private var isVideoFile: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ["mp4", "mov", "webm"].contains(ext)
    }
    
    private var isGif: Bool {
        fileURL.pathExtension.lowercased() == "gif"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Recording Complete")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            // Video preview
            if isVideoFile {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .onAppear {
                        player = AVPlayer(url: fileURL)
                        player?.play()
                        isPlaying = true
                        
                        // Loop playback
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player?.currentItem,
                            queue: .main
                        ) { _ in
                            self.player?.seek(to: .zero)
                            self.player?.play()
                        }
                    }
            } else if isGif {
                AsyncImage(url: fileURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 200)
                .cornerRadius(8)
                .padding(.horizontal)
            } else {
                // Audio waveform placeholder
                VStack {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    Text("Voice Recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // File info
            HStack {
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
                Spacer()
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    Text(formatFileSize(size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Status
            if isSaved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved to Library")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .transition(.opacity)
            }
            
            Divider()
            
            // Action buttons
            VStack(spacing: 8) {
                if !isSaved {
                    Button(action: saveToLibrary) {
                        Label("Save to Library", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                HStack(spacing: 8) {
                    Button(action: openInFinder) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: shareRecording) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                
                if !isSaved {
                    Button(action: { showDeleteAlert = true }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Delete Recording?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
        } message: {
            Text("This recording will be permanently deleted.")
        }
        .onAppear {
            // Auto-save to library
            saveToLibrary()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func saveToLibrary() {
        guard !isSaved else { return }
        
        Task { @MainActor in
            do {
                // Determine type
                let itemType: LibraryItem.ItemType
                let ext = fileURL.pathExtension.lowercased()
                switch ext {
                case "gif":
                    itemType = .gif
                case "m4a":
                    itemType = .voiceRecording
                default:
                    itemType = .recording
                }
                
                // Save to library
                let fileName = fileURL.lastPathComponent
                let name = fileName.replacingOccurrences(of: ".\(ext)", with: "")
                _ = try libraryService.saveRecording(from: fileURL, type: itemType, name: name, collection: "Recordings")
                
                withAnimation {
                    isSaved = true
                }
                
                print("✅ Recording saved to library")
                
                // Close panel after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onClose()
                }
            } catch {
                print("❌ Failed to save to library: \(error)")
            }
        }
    }
    
    private func openInFinder() {
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }
    
    private func shareRecording() {
        let picker = NSSharingServicePicker(items: [fileURL])
        if let contentView = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
    
    private func deleteRecording() {
        recordingService.discardRecording(tempURL: fileURL)
        onClose()
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}