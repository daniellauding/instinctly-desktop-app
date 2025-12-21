import SwiftUI
import AppKit

// MARK: - Helper Functions
func updateAppVisibility(dock: Bool, menuBar: Bool) {
    if dock {
        NSApp.setActivationPolicy(.regular)
    } else {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("playSound") private var playSound = true
    @AppStorage("copyAfterCapture") private var copyAfterCapture = true
    @AppStorage("defaultFormat") private var defaultFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9
    @AppStorage("savePath") private var savePath = ""

    var body: some View {
        TabView {
            GeneralSettingsView(
                launchAtLogin: $launchAtLogin,
                showInDock: $showInDock,
                showInMenuBar: $showInMenuBar,
                playSound: $playSound
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            CaptureSettingsView(
                copyAfterCapture: $copyAfterCapture,
                defaultFormat: $defaultFormat,
                jpegQuality: $jpegQuality,
                savePath: $savePath
            )
            .tabItem {
                Label("Capture", systemImage: "camera.viewfinder")
            }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            CloudSettingsView()
                .tabItem {
                    Label("iCloud", systemImage: "icloud")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @Binding var launchAtLogin: Bool
    @Binding var showInDock: Bool
    @Binding var showInMenuBar: Bool
    @Binding var playSound: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch Instinctly at login", isOn: $launchAtLogin)
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        updateAppVisibility(dock: newValue, menuBar: showInMenuBar)
                    }
                Toggle("Show in Menu Bar", isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { _, newValue in
                        // Ensure at least one is enabled
                        if !newValue && !showInDock {
                            showInDock = true
                        }
                    }
            } header: {
                Text("Appearance")
            } footer: {
                Text("At least one option must be enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Play sound after capture", isOn: $playSound)
            } header: {
                Text("Feedback")
            }

            Section {
                HStack {
                    Text("Menu bar icon")
                    Spacer()
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                }
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Capture Settings
struct CaptureSettingsView: View {
    @Binding var copyAfterCapture: Bool
    @Binding var defaultFormat: String
    @Binding var jpegQuality: Double
    @Binding var savePath: String

    var body: some View {
        Form {
            Section {
                Toggle("Copy to clipboard after capture", isOn: $copyAfterCapture)

                Picker("Default format", selection: $defaultFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("PDF").tag("pdf")
                }

                if defaultFormat == "jpeg" {
                    HStack {
                        Text("JPEG Quality")
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                        Text("\(Int(jpegQuality * 100))%")
                            .frame(width: 40)
                    }
                }
            } header: {
                Text("Capture")
            }

            Section {
                HStack {
                    Text("Save location")
                    Spacer()
                    Text(savePath.isEmpty ? "Default (Pictures)" : savePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Button("Choose...") {
                        chooseSavePath()
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            savePath = url.path
        }
    }
}

// MARK: - Shortcuts Settings
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ShortcutRow(action: "Capture Region", shortcut: "⌘⇧3")
                ShortcutRow(action: "Capture Window", shortcut: "⌘⇧4")
                ShortcutRow(action: "Capture Full Screen", shortcut: "⌘⇧5")
                ShortcutRow(action: "Open from Clipboard", shortcut: "⌘⇧6")
            } header: {
                Text("Capture Shortcuts")
            } footer: {
                Text("Note: These shortcuts may conflict with system shortcuts. Consider using different modifier keys.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                ShortcutRow(action: "Copy to Clipboard", shortcut: "⌘C")
                ShortcutRow(action: "Save", shortcut: "⌘S")
                ShortcutRow(action: "Undo", shortcut: "⌘Z")
                ShortcutRow(action: "Redo", shortcut: "⌘⇧Z")
            } header: {
                Text("Editor Shortcuts")
            }

            Section {
                ForEach(AnnotationTool.allCases) { tool in
                    if let shortcut = tool.shortcut {
                        ShortcutRow(
                            action: tool.rawValue,
                            shortcut: String(shortcut.character).uppercased()
                        )
                    }
                }
            } header: {
                Text("Tool Shortcuts")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

// MARK: - Cloud Settings
struct CloudSettingsView: View {
    @AppStorage("iCloudSync") private var iCloudSync = true
    @AppStorage("syncCollections") private var syncCollections = true
    @AppStorage("syncSettings") private var syncSettings = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable iCloud Sync", isOn: $iCloudSync)

                if iCloudSync {
                    Toggle("Sync collections", isOn: $syncCollections)
                    Toggle("Sync settings", isOn: $syncSettings)
                }
            } header: {
                Text("iCloud")
            }

            if iCloudSync {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Last synced")
                        Spacer()
                        Text("Just now")
                            .foregroundColor(.secondary)
                    }

                    Button("Sync Now") {
                        // Trigger sync
                    }
                } header: {
                    Text("Sync Status")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            // App name & version
            VStack(spacing: 4) {
                Text("Instinctly")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0.0 (1)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Description
            Text("A minimalist screenshot & annotation tool for macOS")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Links
            HStack(spacing: 20) {
                Link("Website", destination: URL(string: "https://instinctly.app")!)
                Link("Privacy Policy", destination: URL(string: "https://instinctly.app/privacy")!)
                Link("Support", destination: URL(string: "https://instinctly.app/support")!)
            }
            .font(.caption)

            // Copyright
            Text("© 2024 Your Company. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
