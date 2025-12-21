import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showColorPopover = false
    @State private var showMoreTools = false

    // Primary tools (always visible)
    private let primaryTools: [AnnotationTool] = [
        .select, .arrow, .rectangle, .text, .highlighter, .blur, .crop
    ]

    // Secondary tools (in "more" menu)
    private let moreTools: [AnnotationTool] = [
        .line, .circle, .freehand, .numberedStep, .callout, .colorPicker
    ]

    var body: some View {
        VStack(spacing: 8) {
            // Primary tools
            ForEach(primaryTools, id: \.self) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: appState.selectedTool == tool
                ) {
                    appState.selectedTool = tool
                }
            }

            // More tools menu
            Menu {
                ForEach(moreTools, id: \.self) { tool in
                    Button {
                        appState.selectedTool = tool
                    } label: {
                        Label(tool.rawValue, systemImage: tool.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(moreTools.contains(appState.selectedTool) ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
            }
            .menuStyle(.borderlessButton)
            .help("More tools")

            Spacer()

            // Color selector
            Button(action: { showColorPopover.toggle() }) {
                Circle()
                    .fill(appState.selectedColor)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showColorPopover) {
                QuickColorPicker(selectedColor: $appState.selectedColor)
            }
            .help("Color")

            // Stroke width
            Menu {
                ForEach([1, 2, 3, 5, 8], id: \.self) { width in
                    Button {
                        appState.strokeWidth = CGFloat(width)
                    } label: {
                        HStack {
                            Text("\(width)px")
                            if Int(appState.strokeWidth) == width {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "lineweight")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .help("Stroke width")
        }
        .padding(.vertical, 8)
        .frame(width: 52)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }
}

// MARK: - Tool Button
struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help("\(tool.rawValue)\(tool.shortcut != nil ? " (\(String(tool.shortcut!.character).uppercased()))" : "")")
    }
}

// MARK: - Quick Color Picker
struct QuickColorPicker: View {
    @Binding var selectedColor: Color

    private let presetColors: [[Color]] = [
        [.red, .orange, .yellow, .green, .blue, .purple],
        [.pink, .brown, .gray, .black, .white, .clear]
    ]

    @State private var customColor: Color = .red

    var body: some View {
        VStack(spacing: 12) {
            // Preset colors grid
            VStack(spacing: 8) {
                ForEach(presetColors.indices, id: \.self) { rowIndex in
                    HStack(spacing: 8) {
                        ForEach(presetColors[rowIndex].indices, id: \.self) { colIndex in
                            let color = presetColors[rowIndex][colIndex]
                            ColorButton(
                                color: color,
                                isSelected: selectedColor == color
                            ) {
                                selectedColor = color
                            }
                        }
                    }
                }
            }

            Divider()

            // System color picker
            ColorPicker("Custom", selection: $customColor)
                .onChange(of: customColor) { oldValue, newValue in
                    selectedColor = newValue
                }
        }
        .padding(12)
        .frame(width: 200)
    }
}

// MARK: - Color Button
struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if color == .clear {
                    // Transparent indicator
                    Image(systemName: "nosign")
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                }

                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ToolbarView()
        .environmentObject(AppState.shared)
        .frame(height: 500)
}
