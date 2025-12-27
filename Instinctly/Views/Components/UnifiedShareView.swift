import SwiftUI

/// Unified sharing component that handles all sharing functionality consistently
struct UnifiedShareView: View {
    let fileURL: URL
    let title: String?
    let initialDescription: String?
    @Binding var isPresented: Bool
    
    // Share configuration
    @State private var shareTitle: String = ""
    @State private var shareDescription: String = ""
    @State private var usePassword: Bool = false
    @State private var password: String = ""
    @State private var isPublic: Bool = false
    @State private var allowComments: Bool = false
    @State private var collection: String = ""
    
    // State management
    @State private var isUploading: Bool = false
    @State private var sharedURL: URL?
    @State private var errorMessage: String?
    @State private var showLinkCopied: Bool = false
    
    // Settings
    @AppStorage("defaultSharePublic") private var defaultSharePublic = false
    @AppStorage("shareUsername") private var shareUsername = ""
    
    @ObservedObject private var shareService = ShareService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            header
            
            if let sharedURL = sharedURL {
                successView(shareURL: sharedURL)
            } else if isUploading {
                uploadingView
            } else {
                configurationView
            }
        }
        .padding(24)
        .frame(width: 450)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear(perform: setupInitialValues)
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sharedURL != nil ? "Link Ready!" : "Share to Cloud")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Success View
    private func successView(shareURL: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("File shared successfully!")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Share URL with comment count
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Share Link:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                HStack(spacing: 8) {
                    Text(shareURL.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    
                    CommentCountView(shareURL: shareURL, size: .small)
                    
                    Button(action: { copyToClipboard(shareURL) }) {
                        Image(systemName: showLinkCopied ? "checkmark" : "doc.on.doc")
                            .foregroundColor(showLinkCopied ? .green : .primary)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Link")
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Share settings summary
            shareSettingsSummary
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(shareURL)
                }
                .buttonStyle(.bordered)
                
                Button("Share Another") {
                    resetForNewShare()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Uploading View
    private var uploadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Uploading to share.instinctly.ai...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !shareTitle.isEmpty {
                Text("\"\(shareTitle)\"")
                    .font(.caption)
                    .italic()
            }
        }
        .frame(height: 120)
    }
    
    // MARK: - Configuration View
    private var configurationView: some View {
        VStack(spacing: 16) {
            // Title and Description
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.headline)
                    TextField("Enter a title for your share...", text: $shareTitle)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description (Optional)")
                        .font(.headline)
                    TextField("Add a description...", text: $shareDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 60)
                }
            }
            
            Divider()
            
            // Privacy and Security Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy & Security")
                    .font(.headline)
                
                HStack {
                    Toggle("Public (anyone with link can view)", isOn: $isPublic)
                    Spacer()
                }
                
                HStack {
                    Toggle("Allow comments", isOn: $allowComments)
                    Spacer()
                }
                
                HStack {
                    Toggle("Password protect", isOn: $usePassword)
                    Spacer()
                }
                
                if usePassword {
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Divider()
            
            // Collection (Optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Collection (Optional)")
                    .font(.headline)
                TextField("Add to collection...", text: $collection)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Button("Share to Cloud") {
                    shareToCloud()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(shareTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    // MARK: - Share Settings Summary
    private var shareSettingsSummary: some View {
        HStack(spacing: 16) {
            if usePassword {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                    Text("Protected")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            HStack(spacing: 4) {
                Image(systemName: isPublic ? "globe" : "lock.shield")
                    .foregroundColor(isPublic ? .blue : .gray)
                Text(isPublic ? "Public" : "Private")
                    .font(.caption)
                    .foregroundColor(isPublic ? .blue : .gray)
            }
            
            if allowComments {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .foregroundColor(.green)
                    Text("Comments On")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            if !collection.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .foregroundColor(.purple)
                    Text(collection)
                        .font(.caption)
                        .foregroundColor(.purple)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Functions
    private func setupInitialValues() {
        shareTitle = title ?? fileURL.deletingPathExtension().lastPathComponent
        shareDescription = initialDescription ?? ""
        isPublic = defaultSharePublic
    }
    
    private func shareToCloud() {
        guard !shareTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Title is required"
            return
        }
        
        if usePassword && password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Password is required when password protection is enabled"
            return
        }
        
        errorMessage = nil
        isUploading = true
        
        Task {
            do {
                let shareURL = try await shareService.uploadFileAndGetShareableLink(
                    fileURL: fileURL,
                    title: shareTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: shareDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : shareDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    collection: collection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : collection.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: (usePassword && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? password.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    isPublic: isPublic,
                    allowComments: allowComments
                )
                
                await MainActor.run {
                    self.sharedURL = shareURL
                    self.isUploading = false
                    copyToClipboard(shareURL)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to share: \(error.localizedDescription)"
                    self.isUploading = false
                }
            }
        }
    }
    
    private func copyToClipboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        
        showLinkCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showLinkCopied = false
        }
    }
    
    private func resetForNewShare() {
        sharedURL = nil
        isUploading = false
        errorMessage = nil
        setupInitialValues()
    }
}

#Preview {
    UnifiedShareView(
        fileURL: URL(fileURLWithPath: "/tmp/test_screenshot.png"),
        title: "Screenshot",
        initialDescription: "My awesome screenshot",
        isPresented: .constant(true)
    )
    .frame(width: 500, height: 600)
    .background(Color(.windowBackgroundColor))
}