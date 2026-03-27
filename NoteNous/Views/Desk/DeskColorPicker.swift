import SwiftUI

// MARK: - Greene-style domain color picker

struct DeskColorPicker: View {
    @Binding var selectedHex: String?
    let onApply: (String?) -> Void

    @State private var showCustomPicker: Bool = false
    @State private var customColor: Color = .gray

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Domain Color")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 4), spacing: 8) {
                ForEach(DeskColor.presets) { preset in
                    colorSwatch(preset)
                }
            }

            Divider()

            HStack {
                Button {
                    showCustomPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 11))
                        Text("Custom")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    selectedHex = nil
                    onApply(nil)
                } label: {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showCustomPicker {
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: customColor) { _, newValue in
                        let hex = newValue.hexString
                        selectedHex = hex
                        onApply(hex)
                    }
            }
        }
        .padding(12)
        .frame(width: 200)
    }

    private func colorSwatch(_ preset: DeskColor) -> some View {
        let isActive = selectedHex == preset.hex
        return Button {
            selectedHex = preset.hex
            onApply(preset.hex)
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(Color(hex: preset.hex))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isActive ? Color.primary : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .overlay {
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                Text(preset.label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(preset.domain)
    }
}

// MARK: - Preset colors (Greene system)

struct DeskColor: Identifiable {
    let id: String
    let hex: String
    let label: String
    let domain: String

    static let presets: [DeskColor] = [
        DeskColor(id: "blue",   hex: "3B82F6", label: "Blue",   domain: "Politics / Law"),
        DeskColor(id: "yellow", hex: "EAB308", label: "Yellow", domain: "War / Strategy"),
        DeskColor(id: "green",  hex: "22C55E", label: "Green",  domain: "Nature / Arts"),
        DeskColor(id: "pink",   hex: "EC4899", label: "Pink",   domain: "Philosophy"),
        DeskColor(id: "orange", hex: "F97316", label: "Orange", domain: "Business"),
        DeskColor(id: "purple", hex: "A855F7", label: "Purple", domain: "Psychology"),
        DeskColor(id: "red",    hex: "EF4444", label: "Red",    domain: "Power"),
        DeskColor(id: "gray",   hex: "6B7280", label: "Gray",   domain: "Other"),
    ]
}
