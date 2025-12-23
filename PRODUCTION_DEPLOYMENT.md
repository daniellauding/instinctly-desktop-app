# Instinctly Production Deployment Guide

## Overview
This guide covers deploying Instinctly to production, including App Store distribution, custom domains, pricing, and mobile development.

## 1. Production Build for Mac App Store

### Prerequisites
- Apple Developer Program membership ($99/year)
- Xcode 15.0 or later
- macOS 13.0 or later for development

### Build Configuration

1. **Update Bundle Identifier**
   ```
   com.yourcompany.instinctly
   ```

2. **Configure Signing & Capabilities**
   - Select "Mac App Store Connect" as distribution method
   - Enable required capabilities:
     - App Sandbox
     - CloudKit
     - Camera
     - Microphone
     - User Selected Files

3. **Update Info.plist**
   ```xml
   <key>CFBundleVersion</key>
   <string>1.0.0</string>
   <key>CFBundleShortVersionString</key>
   <string>1.0</string>
   ```

4. **Archive for Distribution**
   ```bash
   # In Xcode
   Product → Archive
   ```

### App Store Connect Setup

1. **Create App Record**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - Apps → + → New App
   - Fill app metadata

2. **App Information**
   - Name: Instinctly
   - Category: Graphics & Design
   - Content Rights: Your content or licensed content

3. **Pricing Configuration**
   ```
   Price Tier: Choose tier (e.g., $9.99 = Tier 10)
   Availability: All territories or select specific countries
   ```

### Distribution

1. **Upload Binary**
   ```bash
   # Use Application Loader or Transporter
   # Or directly from Xcode Organizer
   ```

2. **Submit for Review**
   - Complete all metadata
   - Add screenshots (1280x800, 1440x900, 2880x1800)
   - Write app description
   - Submit for review

## 2. Direct Distribution (Outside App Store)

### Developer ID Distribution

1. **Configure Developer ID**
   - Use "Developer ID Application" certificate
   - Enable hardened runtime

2. **Archive & Export**
   ```bash
   # Archive in Xcode
   # Export → Developer ID
   ```

3. **Notarization**
   ```bash
   # Submit for notarization
   xcrun notarytool submit Instinctly.app.zip --keychain-profile "notarization"
   
   # Check status
   xcrun notarytool log --keychain-profile "notarization" [submission-id]
   
   # Staple after approval
   xcrun stapler staple Instinctly.app
   ```

4. **Create DMG**
   ```bash
   # Create distribution package
   hdiutil create -srcfolder Instinctly.app -volname "Instinctly" Instinctly.dmg
   ```

## 3. Campaign Codes & Pricing

### App Store Promo Codes

1. **Generate Promo Codes**
   - App Store Connect → Apps → Promo Codes
   - Generate up to 100 codes per quarter
   - Track usage and redemptions

2. **Campaign Tracking**
   ```swift
   // Add to AppDelegate.swift
   func trackCampaignSource(_ source: String) {
       UserDefaults.standard.set(source, forKey: "campaignSource")
       // Send to analytics
   }
   ```

### Custom Pricing

1. **Price Tiers**
   ```
   Tier 1:  Free
   Tier 5:  $2.99
   Tier 10: $9.99
   Tier 15: $19.99
   Tier 20: $29.99
   ```

2. **Regional Pricing**
   - Auto-convert prices to local currencies
   - Or set custom prices per territory

### Launch Pricing Strategy
```
Phase 1: Launch at $4.99 (Early Bird)
Phase 2: Regular price $9.99 after 30 days
Phase 3: Premium features $19.99
```

## 4. Custom Domain for Sharable Links

### DNS Configuration

1. **Setup Subdomain**
   ```
   Type: CNAME
   Name: share
   Value: your-hosting-provider.com
   TTL: 3600
   ```

2. **Example for share.instinctly.com**
   ```bash
   # If using GitHub Pages
   CNAME: yourusername.github.io
   
   # If using Vercel
   CNAME: cname.vercel-dns.com
   
   # If using Netlify
   CNAME: [site-name].netlify.app
   ```

### Hosting Options

#### Option A: GitHub Pages (Free)
```bash
# Create repository: instinctly-web-viewer
# Upload Web/index.html
# Enable Pages in repository settings
# Custom domain: share.instinctly.com
```

#### Option B: Vercel (Free)
```bash
# Connect GitHub repository
# Deploy automatically
# Add custom domain in Vercel dashboard
```

#### Option C: AWS CloudFront + S3
```bash
# Upload to S3 bucket
# Setup CloudFront distribution
# Configure custom domain with SSL
```

### Update App Configuration

```swift
// In ShareService.swift
private let webViewerBaseURL = "https://share.instinctly.com"

// Update CloudKit container identifier
private let containerIdentifier = "iCloud.com.yourcompany.instinctly"
```

## 5. iOS & iPadOS Development

### Project Setup

1. **Create iOS Target**
   ```bash
   # In Xcode
   File → New → Target → iOS App
   Target Name: Instinctly iOS
   ```

2. **Shared Framework**
   ```bash
   # Create shared framework target
   File → New → Target → Framework
   Target Name: InstinctlyCore
   ```

### Code Sharing Strategy

```swift
// InstinctlyCore framework structure
InstinctlyCore/
├── Models/
│   ├── Annotation.swift
│   └── CaptureSession.swift
├── Services/
│   ├── CloudSyncService.swift
│   ├── ShareService.swift
│   └── LibraryService.swift
└── Utilities/
    ├── Extensions/
    └── Helpers/
```

### iOS-Specific Features

1. **Screen Recording** (iOS 11+)
   ```swift
   import ReplayKit
   
   class iOSScreenRecordingService {
       let recorder = RPScreenRecorder.shared()
       
       func startRecording() {
           recorder.startRecording { error in
               // Handle recording
           }
       }
   }
   ```

2. **Screenshots** (iOS)
   ```swift
   import UIKit
   
   extension UIView {
       func asImage() -> UIImage {
           let renderer = UIGraphicsImageRenderer(bounds: bounds)
           return renderer.image { rendererContext in
               layer.render(in: rendererContext.cgContext)
           }
       }
   }
   ```

3. **Photo Library Integration**
   ```swift
   import Photos
   
   func saveToPhotoLibrary(_ image: UIImage) {
       PHPhotoLibrary.requestAuthorization { status in
           guard status == .authorized else { return }
           UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
       }
   }
   ```

### SwiftUI Views (Cross-platform)

```swift
// Shared annotation view
struct AnnotationView: View {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif
    
    var body: some View {
        // Cross-platform implementation
    }
}
```

### Platform-Specific UI

```swift
// iOS/iPadOS specific views
struct iOSMainView: View {
    var body: some View {
        NavigationView {
            SidebarView()
            EditorView()
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}

// iPad-specific features
struct iPadCanvasView: View {
    var body: some View {
        CanvasView()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // iPad-optimized toolbar
                }
            }
    }
}
```

### Deployment Strategy

1. **iOS App Store**
   ```
   Bundle ID: com.yourcompany.instinctly.ios
   Deployment Target: iOS 15.0+
   Device Support: iPhone, iPad
   ```

2. **Feature Parity Matrix**
   ```
   Feature                | macOS | iOS | iPadOS
   ----------------------|-------|-----|--------
   Screenshot Capture    |   ✓   |  ✓  |   ✓
   Screen Recording      |   ✓   |  ✓  |   ✓
   Annotation Tools      |   ✓   |  ✓  |   ✓
   Cloud Sharing         |   ✓   |  ✓  |   ✓
   Library Management    |   ✓   |  ✓  |   ✓
   Window Selection      |   ✓   |  —  |   —
   Menu Bar Integration  |   ✓   |  —  |   —
   Touch Gestures        |   —   |  ✓  |   ✓
   Apple Pencil Support  |   —   |  —  |   ✓
   ```

## 6. Marketing & Launch Strategy

### App Store Optimization (ASO)

1. **Keywords**
   ```
   Primary: screenshot, screen recording, annotation
   Secondary: productivity, design tools, sharing
   Long-tail: screen capture with annotation tools
   ```

2. **App Store Listing**
   ```
   Title: Instinctly - Screenshot & Screen Recording
   Subtitle: Powerful annotation and sharing tools
   ```

### Launch Checklist

- [ ] App Store listing complete
- [ ] Screenshots and app preview video
- [ ] Press kit and media assets
- [ ] Website landing page
- [ ] Social media accounts
- [ ] Beta testing program
- [ ] User documentation
- [ ] Support email/system
- [ ] Analytics tracking
- [ ] Crash reporting

### Post-Launch

1. **Update Schedule**
   ```
   Week 1: Bug fixes and user feedback
   Month 1: Feature updates based on reviews
   Month 3: Major feature release
   ```

2. **Metrics to Track**
   ```
   - Download numbers
   - User retention (D1, D7, D30)
   - App Store ratings
   - Support ticket volume
   - Feature usage analytics
   ```

## 7. Technical Requirements

### Minimum System Requirements
```
macOS: 13.0 (Ventura) or later
iOS: 15.0 or later
iPadOS: 15.0 or later
Xcode: 15.0 or later (for development)
```

### Dependencies
```
CloudKit: Built-in framework
SwiftUI: iOS 15.0+, macOS 12.0+
ReplayKit: iOS 11.0+ (for screen recording)
AVFoundation: All platforms (for media processing)
```

### Performance Targets
```
App launch time: < 2 seconds
Screenshot capture: < 1 second
Memory usage: < 100MB baseline
Export time: 1080p video < 30 seconds
```

This guide provides a comprehensive roadmap for taking Instinctly from development to production across all Apple platforms.