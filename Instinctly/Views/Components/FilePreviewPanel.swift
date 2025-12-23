import SwiftUI
import AppKit
import AVKit
import AVFoundation

// MARK: - File Preview Panel
struct FilePreviewPanel: View {
    let fileURL: URL
    @Binding var isPresented: Bool
    @State private var isLoading = true
    @State private var previewContent: PreviewContent?
    @State private var showShareSheet = false
    @StateObject private var shareService = ShareService.shared
    
    enum PreviewContent {
        case image(NSImage)
        case gif(NSImage)
        case video(AVPlayer)
        case audio
        case error(String)
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(formatFileInfo())
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: shareToCloud) {
                            if shareService.isSharing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "link.badge.plus")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Share to iCloud URL")
                        .disabled(shareService.isSharing)
                        
                        Button(action: openInFinder) {
                            Image(systemName: "folder")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                        
                        Button(action: openExternal) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Open in Default App")
                        
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                }
                .padding(20)
                
                // Content area
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(maxWidth: 800, maxHeight: 600)
                    
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading...")
                                .foregroundColor(.secondary)
                        }
                    } else if let content = previewContent {
                        switch content {
                        case .image(let nsImage), .gif(let nsImage):
                            GeometryReader { geometry in
                                ScrollView([.horizontal, .vertical]) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(
                                            maxWidth: geometry.size.width - 40,
                                            maxHeight: geometry.size.height - 40
                                        )
                                        .clipped()
                                }
                                .frame(maxWidth: 800, maxHeight: 600)
                            }
                            .frame(maxWidth: 800, maxHeight: 600)
                            
                        case .video(let player):
                            VideoPlayer(player: player)
                                .frame(maxWidth: 800, maxHeight: 600)
                                .cornerRadius(8)
                                .onAppear {
                                    player.play()
                                }
                                .onDisappear {
                                    player.pause()
                                    player.seek(to: .zero)
                                }
                            
                        case .audio:
                            VStack(spacing: 20) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 64))
                                    .foregroundColor(.secondary)
                                
                                Text("Audio File")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                
                                Text(fileURL.lastPathComponent)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button("Play in Default App") {
                                    openExternal()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(40)
                            
                        case .error(let message):
                            VStack(spacing: 20) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 64))
                                    .foregroundColor(.orange)
                                
                                Text("Preview Error")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                
                                Text(message)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(40)
                        }
                    }
                }
                .frame(maxWidth: 800, maxHeight: 600)
                .padding(.bottom, 20)
                
                // Footer with keyboard shortcuts and share result
                VStack(spacing: 8) {
                    if let shareURL = shareService.lastSharedURL {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Shared to iCloud:")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                
                                HStack {
                                    Text(shareURL.absoluteString)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
                                    Button(action: { shareService.copyLinkToClipboard(shareURL) }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy Link")
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    HStack {
                        Text("Press ESC to close")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            loadPreview()
        }
        .onKeyDown { key in
            if key.characters == "\u{1B}" { // ESC key
                isPresented = false
                return true
            }
            return false
        }
    }
    
    private func shareToCloud() {
        Task {
            do {
                let shareURL = try await shareService.uploadFileAndGetShareableLink(fileURL: fileURL)
                await MainActor.run {
                    // Show success - the URL is already stored in shareService.lastSharedURL
                    print("✅ File shared to iCloud: \(shareURL.absoluteString)")
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to share file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadPreview() {
        isLoading = true
        
        Task {
            let content = await generatePreviewContent()
            await MainActor.run {
                previewContent = content
                isLoading = false
            }
        }
    }
    
    private func generatePreviewContent() async -> PreviewContent {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        switch fileExtension {
        case "png", "jpg", "jpeg":
            if let image = NSImage(contentsOf: fileURL) {
                return .image(image)
            } else {
                return .error("Unable to load image")
            }
            
        case "gif":
            if let image = NSImage(contentsOf: fileURL) {
                return .gif(image)
            } else {
                return .error("Unable to load GIF")
            }
            
        case "mp4", "mov", "webm":
            let asset = AVURLAsset(url: fileURL)
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            return .video(player)
            
        case "m4a":
            return .audio
            
        default:
            return .error("File type not supported for preview")
        }
    }
    
    private func formatFileInfo() -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            var info: [String] = []
            
            // File size
            if let size = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                info.append(formatter.string(fromByteCount: size))
            }
            
            // File type
            let ext = fileURL.pathExtension.uppercased()
            if !ext.isEmpty {
                info.append(ext)
            }
            
            // Date modified
            if let date = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                info.append(formatter.string(from: date))
            }
            
            return info.joined(separator: " • ")
        } catch {
            return fileURL.pathExtension.uppercased()
        }
    }
    
    private func openInFinder() {
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }
    
    private func openExternal() {
        NSWorkspace.shared.open(fileURL)
    }
}

// MARK: - Key Down Modifier
extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Bool) -> some View {
        background(KeyDownView(onKeyDown: action))
    }
}

struct KeyDownView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyDownNSView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyDownNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if let onKeyDown = onKeyDown, onKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

#Preview {
    FilePreviewPanel(
        fileURL: URL(fileURLWithPath: "/tmp/test.gif"),
        isPresented: .constant(true)
    )
}