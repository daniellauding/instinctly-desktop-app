import SwiftUI
import AppKit

struct ColorPickerPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var hexValue: String = ""
    @State private var red: Double = 255
    @State private var green: Double = 0
    @State private var blue: Double = 0
    @State private var alpha: Double = 1.0

    @State private var pickedColorInfo: PickedColorInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Color")
                    .font(.headline)
                Spacer()

                Button(action: activateEyedropper) {
                    Label("Pick from Image", systemImage: "eyedropper")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Color Preview
            HStack(spacing: 12) {
                // Current color
                RoundedRectangle(cornerRadius: 8)
                    .fill(appState.selectedColor)
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    )

                // Color info
                VStack(alignment: .leading, spacing: 4) {
                    if let info = pickedColorInfo {
                        Text("Position: \(Int(info.position.x)), \(Int(info.position.y))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Hex value (copyable)
                    HStack {
                        Text(hexValue.isEmpty ? "#FF0000" : hexValue)
                            .font(.system(.body, design: .monospaced))

                        Button(action: copyHexToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Copy hex value")
                    }

                    Text("RGB: \(Int(red)), \(Int(green)), \(Int(blue))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Hex Input
            HStack {
                Text("Hex")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)

                TextField("#FFFFFF", text: $hexValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: hexValue) { _, newValue in
                        updateFromHex(newValue)
                    }
            }

            // RGB Sliders
            VStack(spacing: 8) {
                ColorSlider(label: "R", value: $red, color: .red)
                ColorSlider(label: "G", value: $green, color: .green)
                ColorSlider(label: "B", value: $blue, color: .blue)
                ColorSlider(label: "A", value: Binding(
                    get: { alpha * 255 },
                    set: { alpha = $0 / 255 }
                ), color: .gray)
            }
            .onChange(of: red) { _, _ in updateColor() }
            .onChange(of: green) { _, _ in updateColor() }
            .onChange(of: blue) { _, _ in updateColor() }
            .onChange(of: alpha) { _, _ in updateColor() }

            Divider()

            // Preset Colors
            Text("Presets")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(presetColors, id: \.self) { color in
                    Button(action: { selectColor(color) }) {
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        appState.selectedColor == color ? Color.primary : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Recent Colors
            if !recentColors.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(recentColors.prefix(8), id: \.self) { color in
                        Button(action: { selectColor(color) }) {
                            Circle()
                                .fill(color)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            syncFromAppState()
        }
        .onChange(of: appState.selectedColor) { _, _ in
            syncFromAppState()
        }
    }

    // MARK: - Preset Colors
    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple,
        .pink, .cyan, .mint, .indigo, .brown, .gray,
        .black, .white,
        Color(red: 1, green: 0.5, blue: 0),
        Color(red: 0, green: 0.5, blue: 0),
        Color(red: 0.5, green: 0, blue: 0.5),
        Color(red: 0.5, green: 0.5, blue: 0.5)
    ]

    @State private var recentColors: [Color] = []

    // MARK: - Methods

    private func activateEyedropper() {
        appState.selectedTool = .colorPicker
    }

    private func selectColor(_ color: Color) {
        appState.selectedColor = color
        addToRecent(color)
    }

    private func addToRecent(_ color: Color) {
        recentColors.removeAll { $0 == color }
        recentColors.insert(color, at: 0)
        if recentColors.count > 10 {
            recentColors.removeLast()
        }
    }

    private func syncFromAppState() {
        let nsColor = NSColor(appState.selectedColor)
        if let rgb = nsColor.usingColorSpace(.sRGB) {
            red = Double(rgb.redComponent * 255)
            green = Double(rgb.greenComponent * 255)
            blue = Double(rgb.blueComponent * 255)
            alpha = Double(rgb.alphaComponent)
            hexValue = String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
        }
    }

    private func updateColor() {
        let color = Color(
            red: red / 255,
            green: green / 255,
            blue: blue / 255,
            opacity: alpha
        )
        appState.selectedColor = color
        hexValue = String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    private func updateFromHex(_ hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleanHex.count == 6,
              let hexInt = UInt64(cleanHex, radix: 16) else { return }

        red = Double((hexInt >> 16) & 0xFF)
        green = Double((hexInt >> 8) & 0xFF)
        blue = Double(hexInt & 0xFF)

        let color = Color(
            red: red / 255,
            green: green / 255,
            blue: blue / 255,
            opacity: alpha
        )
        appState.selectedColor = color
    }

    private func copyHexToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hexValue, forType: .string)
    }
}

// MARK: - Color Slider
struct ColorSlider: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .leading)

            Slider(value: $value, in: 0...255)
                .tint(color)

            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

// MARK: - Picked Color Info
struct PickedColorInfo {
    let color: Color
    let position: CGPoint
    let hex: String
    let rgb: (r: Int, g: Int, b: Int)
}

#Preview {
    ColorPickerPanel()
        .environmentObject(AppState.shared)
        .frame(width: 250, height: 500)
}
