# Instinctly

A powerful screenshot and screen recording app for macOS with annotation tools, cloud sharing, and library management.

## Features

- **Screenshot Capture**: Region, window, or fullscreen capture
- **Screen Recording**: Record screen with audio, microphone, and optional webcam overlay
- **Annotation Tools**: Arrow, rectangle, circle, text, blur, highlight, and more
- **Library Management**: Organize screenshots and recordings in collections
- **Cloud Sharing**: Share via iCloud with shareable web links
- **Export Options**: PNG, JPEG, PDF, MP4, GIF, MOV formats

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Apple Developer Account (for CloudKit features)

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/daniellauding/instinctly-app.git
cd instinctly-app
```

### 2. Open in Xcode

```bash
open Instinctly/Instinctly.xcodeproj
```

Or double-click the `Instinctly.xcodeproj` file in Finder.

### 3. Configure Signing & Capabilities

1. Select the **Instinctly** target in the project navigator
2. Go to **Signing & Capabilities** tab
3. Select your **Team** from the dropdown
4. Change the **Bundle Identifier** to your own (e.g., `com.yourname.instinctly`)

### 4. Configure Entitlements

The app requires the following entitlements (already configured in `Instinctly.entitlements`):

- App Sandbox
- Camera access (for webcam recording)
- Microphone access (for audio recording)
- User Selected File (Read/Write)
- Outgoing Network Connections (for CloudKit)

### 5. Set Up CloudKit (Optional - for Cloud Sharing)

If you want to enable cloud sharing features:

#### a. Create iCloud Container

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles** > **Identifiers**
3. Click **+** to create a new identifier
4. Select **iCloud Containers** and click Continue
5. Enter a description and identifier (e.g., `iCloud.com.yourname.instinctly`)
6. Click Register

#### b. Link Container to App ID

1. In Identifiers, find your App ID
2. Click to edit it
3. Enable **iCloud** capability
4. Click **Configure** next to iCloud
5. Check **CloudKit**
6. Select your iCloud container
7. Save

#### c. Update App Configuration

1. In Xcode, go to **Signing & Capabilities**
2. Add **iCloud** capability if not present
3. Check **CloudKit**
4. Select your container

#### d. Create CloudKit Schema

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com)
2. Select your container
3. Go to **Schema** > **Record Types**
4. Create a record type called `SharedImage` with fields:
   - `title` (String)
   - `createdAt` (Date/Time)
   - `imageAsset` (Asset)
   - `annotationsJSON` (String)

#### e. Generate API Token (for Web Viewer)

1. In CloudKit Dashboard, go to **API Access**
2. Click **Create New Token**
3. Copy the token
4. Update `Web/index.html` with your token

### 6. Build and Run

1. Select the **Instinctly** scheme
2. Choose **My Mac** as the destination
3. Press `Cmd + R` to build and run

## Project Structure

```
Instinctly/
├── Instinctly/
│   ├── InstinctlyApp.swift          # App entry point
│   ├── AppState.swift               # Global app state
│   ├── Models/
│   │   └── Annotation.swift         # Annotation data models
│   ├── Views/
│   │   ├── MainWindowView.swift     # Main editor window
│   │   ├── MenuBarView.swift        # Menu bar interface
│   │   ├── SettingsView.swift       # Preferences
│   │   ├── Collections/
│   │   │   └── CollectionsView.swift # Library browser
│   │   └── Components/
│   │       ├── ExportOptionsSheet.swift
│   │       └── RecordingControlsView.swift
│   ├── Services/
│   │   ├── ScreenCaptureService.swift    # Screenshot capture
│   │   ├── ScreenRecordingService.swift  # Screen recording
│   │   ├── ImageProcessingService.swift  # Image manipulation
│   │   ├── LibraryService.swift          # Local library management
│   │   ├── ShareService.swift            # Cloud sharing
│   │   └── CloudSyncService.swift        # CloudKit sync
│   ├── Drawing/
│   │   └── AnnotationView.swift     # Annotation rendering
│   └── Helpers/
│       └── KeyboardShortcuts.swift  # Global hotkeys
├── Web/
│   ├── index.html                   # Web viewer for shared images
│   └── README.md                    # Web viewer setup guide
└── README.md                        # This file
```

## Usage

### Capturing Screenshots

1. Click the menu bar icon or use keyboard shortcut
2. Select capture mode: Region, Window, or Fullscreen
3. Make your selection
4. Edit with annotation tools
5. Save or share

### Recording Screen

1. Click **Record** in menu bar
2. Choose recording mode and options
3. Select region or window
4. Click **Stop** when done
5. Save to desired location

### Managing Library

1. Open main window
2. Navigate to **Collections** in sidebar
3. View screenshots and recordings
4. Create custom collections
5. Mark favorites with star

### Sharing

1. Capture or open an image
2. Click **Share** or use Export menu
3. Choose sharing method:
   - Copy to clipboard
   - Save to disk
   - Generate cloud link (requires iCloud setup)

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Capture Region | `Cmd + Shift + 4` |
| Capture Window | `Cmd + Shift + 5` |
| Capture Fullscreen | `Cmd + Shift + 3` |
| Start Recording | `Cmd + Shift + R` |
| Open Library | `Cmd + L` |
| Settings | `Cmd + ,` |

## Troubleshooting

### "Sandbox entitlement" errors

1. Clean build folder: `Cmd + Shift + K`
2. Delete derived data: `~/Library/Developer/Xcode/DerivedData`
3. Rebuild

### Screen recording permissions

1. Go to **System Settings** > **Privacy & Security** > **Screen Recording**
2. Enable Instinctly
3. Restart the app

### Camera/Microphone not working

1. Go to **System Settings** > **Privacy & Security**
2. Enable permissions for Camera and Microphone
3. Restart the app

### CloudKit errors

1. Ensure you're signed into iCloud on your Mac
2. Check that the container is properly linked
3. Verify the schema exists in CloudKit Dashboard

## License

Copyright 2024. All rights reserved.

## Support

For issues and feature requests, please open an issue on GitHub.
