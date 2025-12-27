# 🔥 Firebase Setup Guide for Instinctly

This guide walks you through setting up Firebase for user authentication, file storage, and database functionality while maintaining iCloud as a fallback option.

## 📋 Table of Contents
1. [Firebase Project Setup](#1-firebase-project-setup)
2. [Firebase Services Configuration](#2-firebase-services-configuration)
3. [iOS/macOS App Configuration](#3-iosmacos-app-configuration)
4. [Add Firebase SDK to Xcode](#4-add-firebase-sdk-to-xcode)
5. [Code Integration](#5-code-integration)
6. [Migration Strategy](#6-migration-strategy)

---

## 1. Firebase Project Setup

### Step 1: Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click **"Create a project"** or **"Add project"**
3. Enter project name: `instinctly-app`
4. Enable Google Analytics (optional but recommended)
5. Select or create a Google Analytics account
6. Click **"Create project"**

### Step 2: Add Your App
1. In Firebase Console, click the **iOS+** icon to add an iOS/macOS app
2. Register your app:
   - **Apple bundle ID**: `com.instinctly.app` (match your Xcode project)
   - **App nickname**: Instinctly Desktop
   - **App Store ID**: (leave blank for now)
3. Click **"Register app"**

### Step 3: Download Configuration File
1. Download the `GoogleService-Info.plist` file
2. **IMPORTANT**: Save this file to add to your Xcode project later
3. Click **"Next"** through the remaining steps

---

## 2. Firebase Services Configuration

### Authentication Setup
1. In Firebase Console, go to **Authentication** → **Sign-in method**
2. Enable the following providers:
   - ✅ **Email/Password**: Click Enable
   - ✅ **Google**: Configure with your OAuth client
   - ✅ **Apple**: Configure with Apple Developer credentials
   - ✅ **Anonymous**: Enable for guest access

### Firestore Database Setup
1. Go to **Firestore Database** → **Create database**
2. Choose **"Start in test mode"** (we'll secure it later)
3. Select location: `us-central1` (or nearest to your users)
4. Click **"Enable"**

#### Database Structure:
```javascript
// Collections structure
instinctly-app/
├── users/
│   └── {userId}/
│       ├── profile: { displayName, email, createdAt, plan }
│       └── settings: { theme, notifications, preferences }
├── recordings/
│   └── {userId}/
│       └── items/
│           └── {recordingId}/
│               ├── metadata: { title, duration, format, createdAt }
│               ├── shareSettings: { isPublic, password, allowComments }
│               └── storageRef: "recordings/{userId}/{recordingId}/file.mp4"
├── collections/
│   └── {userId}/
│       └── {collectionId}/
│           ├── metadata: { name, description, isPublic }
│           └── items: [ recordingIds ]
├── shared/
│   └── {shareId}/
│       ├── originalOwner: userId
│       ├── recordingId: recordingId
│       ├── shareSettings: { password, expiresAt }
│       └── comments: [ { userId, text, timestamp } ]
└── comments/
    └── {shareId}/
        └── {commentId}/
            ├── userId: string
            ├── text: string
            └── timestamp: Date
```

### Storage Setup
1. Go to **Storage** → **Get started**
2. Start in test mode (we'll add rules later)
3. Choose location (same as Firestore)
4. Click **"Done"**

#### Storage Structure:
```
gs://instinctly-app.appspot.com/
├── recordings/
│   └── {userId}/
│       └── {recordingId}/
│           ├── original.mp4
│           ├── thumbnail.jpg
│           └── processed/
│               ├── trimmed.mp4
│               └── compressed.mp4
├── profiles/
│   └── {userId}/
│       └── avatar.jpg
└── temp/
    └── {sessionId}/
        └── upload.tmp
```

### Security Rules (Production)

#### Firestore Rules:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own data
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Recordings: users can access their own
    match /recordings/{userId}/items/{recordingId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Shared items: public read, owner write
    match /shared/{shareId} {
      allow read: if resource.data.shareSettings.isPublic == true;
      allow write: if request.auth != null && request.auth.uid == resource.data.originalOwner;
    }
    
    // Comments: authenticated users can comment
    match /comments/{shareId}/{commentId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && request.auth.uid == resource.data.userId;
    }
  }
}
```

#### Storage Rules:
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Users can access their own recordings
    match /recordings/{userId}/{recordingId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Profile pictures
    match /profiles/{userId}/{fileName} {
      allow read: if true;  // Public profiles
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Temporary uploads
    match /temp/{sessionId}/{fileName} {
      allow write: if request.auth != null;
      allow read: if request.auth != null;
    }
  }
}
```

---

## 3. iOS/macOS App Configuration

### Enable Required Capabilities in Xcode:
1. Open your project in Xcode
2. Select your target → **Signing & Capabilities**
3. Add capabilities:
   - ✅ **Sign in with Apple** (if using Apple sign-in)
   - ✅ **Keychain Sharing** (for secure credential storage)
   - ✅ **Background Modes** → Background fetch (for sync)

### Add URL Schemes:
1. In Xcode, select your target → **Info**
2. Add URL Type:
   - **Identifier**: `com.instinctly.app`
   - **URL Schemes**: `instinctly`
3. For Google Sign-In, add another:
   - **URL Schemes**: (REVERSED_CLIENT_ID from GoogleService-Info.plist)

---

## 4. Add Firebase SDK to Xcode

### Using Swift Package Manager:
1. In Xcode: **File** → **Add Package Dependencies**
2. Enter Firebase SDK URL: `https://github.com/firebase/firebase-ios-sdk`
3. Choose version: **Up to Next Major Version** → `11.0.0`
4. Select packages:
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
   - ✅ FirebaseAnalytics (optional)
5. Click **Add Package**

### Add GoogleService-Info.plist:
1. Drag `GoogleService-Info.plist` into your Xcode project
2. Make sure it's added to your app target
3. Place it in `Instinctly/Resources/`

---

## 5. Code Integration

### Initialize Firebase (AppDelegate.swift):
```swift
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Configure Firestore settings
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true  // Offline support
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        Firestore.firestore().settings = settings
        
        // Check authentication state
        Auth.auth().addStateDidChangeListener { auth, user in
            if let user = user {
                print("User signed in: \(user.email ?? "unknown")")
            } else {
                print("User signed out")
            }
        }
    }
}
```

### Firebase Service (Create New File):
```swift
// Instinctly/Services/FirebaseService.swift
import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    init() {
        setupAuthListener()
    }
    
    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isAuthenticated = user != nil
        }
    }
    
    // MARK: - Authentication
    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }
    
    func signUp(email: String, password: String, displayName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        
        // Update display name
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()
        
        // Create user document
        try await createUserDocument(for: result.user)
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
    
    // MARK: - Firestore
    private func createUserDocument(for user: User) async throws {
        let userData: [String: Any] = [
            "displayName": user.displayName ?? "",
            "email": user.email ?? "",
            "createdAt": Timestamp(),
            "plan": "free"
        ]
        
        try await db.collection("users")
            .document(user.uid)
            .setData(userData)
    }
    
    // MARK: - Storage
    func uploadRecording(fileURL: URL, metadata: [String: Any]) async throws -> String {
        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let recordingId = UUID().uuidString
        let storageRef = storage.reference()
            .child("recordings")
            .child(userId)
            .child(recordingId)
            .child(fileURL.lastPathComponent)
        
        // Upload file
        _ = try await storageRef.putFileAsync(from: fileURL)
        
        // Get download URL
        let downloadURL = try await storageRef.downloadURL()
        
        // Save metadata to Firestore
        var recordingData = metadata
        recordingData["storageURL"] = downloadURL.absoluteString
        recordingData["createdAt"] = Timestamp()
        
        try await db.collection("recordings")
            .document(userId)
            .collection("items")
            .document(recordingId)
            .setData(recordingData)
        
        return recordingId
    }
}

enum FirebaseError: Error {
    case notAuthenticated
    case uploadFailed
    case documentNotFound
}
```

### Update FirebaseAuthView:
Replace the TODO comments in `FirebaseAuthView.swift` with actual Firebase calls:

```swift
// In authenticate() function:
private func authenticate() {
    isLoading = true
    errorMessage = ""
    
    Task {
        do {
            if isLoginMode {
                try await FirebaseService.shared.signIn(
                    email: email, 
                    password: password
                )
            } else {
                try await FirebaseService.shared.signUp(
                    email: email, 
                    password: password, 
                    displayName: displayName
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            showingAlert = true
        }
        isLoading = false
    }
}
```

---

## 6. Migration Strategy

### Phase 1: Dual Operation (Current)
- ✅ Keep iCloud as primary storage
- ✅ Add Firebase authentication UI
- ✅ Test Firebase connections

### Phase 2: Parallel Sync (Next 2-4 weeks)
```swift
class HybridStorageService {
    func saveRecording(_ url: URL) async {
        // Save to iCloud (existing)
        await saveToICloud(url)
        
        // Also save to Firebase if authenticated
        if FirebaseService.shared.isAuthenticated {
            try? await FirebaseService.shared.uploadRecording(
                fileURL: url, 
                metadata: [:]
            )
        }
    }
}
```

### Phase 3: Firebase Primary (4-6 weeks)
- Make Firebase the primary storage
- Keep iCloud as backup/offline cache
- Sync between both systems

### Phase 4: Full Migration (6-8 weeks)
- Firebase as sole cloud provider
- iCloud only for local cache
- Complete feature parity

---

## 🎯 Next Steps

1. **Create Firebase Project** following steps above
2. **Download GoogleService-Info.plist**
3. **Add Firebase SDK** to Xcode project
4. **Test authentication** with the FirebaseAuthView
5. **Implement gradual migration** starting with dual storage

## 🔐 Important Security Notes

- Never commit `GoogleService-Info.plist` to public repos
- Use environment variables for sensitive keys
- Enable App Check for production
- Implement rate limiting for API calls
- Use Security Rules to protect user data

## 📱 Testing Checklist

- [ ] User can create account
- [ ] User can sign in/out
- [ ] Files upload to Firebase Storage
- [ ] Metadata saves to Firestore
- [ ] iCloud still works as fallback
- [ ] Offline mode functions correctly

---

## Support Resources

- [Firebase Documentation](https://firebase.google.com/docs)
- [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk)
- [Firestore Data Modeling](https://firebase.google.com/docs/firestore/data-model)
- [Storage Best Practices](https://firebase.google.com/docs/storage/web/upload-files)

This setup maintains iCloud functionality while gradually introducing Firebase features, ensuring a smooth transition without breaking existing functionality.