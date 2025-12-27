import SwiftUI

/// Reusable component to show comment count indicator for shared content
struct CommentCountView: View {
    let shareURL: URL?
    let size: CommentCountSize
    @StateObject private var shareService = ShareService.shared
    
    enum CommentCountSize {
        case small, medium, large
        
        var iconFont: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .body
            }
        }
        
        var textFont: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .callout
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
            case .medium: return EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
            case .large: return EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
            }
        }
    }
    
    init(shareURL: URL?, size: CommentCountSize = .medium) {
        self.shareURL = shareURL
        self.size = size
    }
    
    var body: some View {
        Group {
            if let shareURL = shareURL,
               let shareId = extractShareId(from: shareURL),
               let commentCount = shareService.commentCounts[shareId],
               commentCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                        .font(size.iconFont)
                        .foregroundColor(.orange)
                    Text("\(commentCount)")
                        .font(size.textFont)
                        .foregroundColor(.orange)
                }
                .padding(size.padding)
                .background(.orange.opacity(0.15))
                .clipShape(Capsule())
                .help("\(commentCount) comment\(commentCount == 1 ? "" : "s")")
            }
        }
        .onAppear {
            fetchCommentCountIfNeeded()
        }
        .onChange(of: shareURL) { _ in
            fetchCommentCountIfNeeded()
        }
    }
    
    private func fetchCommentCountIfNeeded() {
        guard let shareURL = shareURL,
              let shareId = extractShareId(from: shareURL),
              shareService.commentCounts[shareId] == nil else { return }
        
        Task {
            try? await shareService.fetchCommentCount(for: shareId)
        }
    }
    
    private func extractShareId(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idItem = queryItems.first(where: { $0.name == "id" }) else {
            return nil
        }
        return idItem.value
    }
}

#Preview {
    VStack(spacing: 16) {
        CommentCountView(
            shareURL: URL(string: "https://daniellauding.github.io/instinctly-share?id=test-123"),
            size: .small
        )
        
        CommentCountView(
            shareURL: URL(string: "https://daniellauding.github.io/instinctly-share?id=test-456"),
            size: .medium
        )
        
        CommentCountView(
            shareURL: URL(string: "https://daniellauding.github.io/instinctly-share?id=test-789"),
            size: .large
        )
    }
    .padding()
    .onAppear {
        // Mock some comment data for preview
        ShareService.shared.commentCounts["test-123"] = 3
        ShareService.shared.commentCounts["test-456"] = 12
        ShareService.shared.commentCounts["test-789"] = 99
    }
}