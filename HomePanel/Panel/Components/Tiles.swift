import SwiftUI

/// Square Control Center style tile with two tap areas:
/// the icon circle toggles, the rest of the tile opens the device screen.
struct EntityTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isOn: Bool
    var isAvailable: Bool = true
    /// Icon circle fill when on (yellow for switches, the light's color for WLED).
    var onColor: Color = Theme.bulbYellow
    /// Light circle → dark symbol. The yellow bulb uses a white symbol.
    var onColorIsLight: Bool = false
    /// What the icon does, for VoiceOver (default "Turn X on/off").
    var iconActionLabel: String?
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(isAvailable ? subtitle : "Unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(isOn ? Theme.onSecondaryText : Color.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(isOn ? Theme.onText : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(10)
                .background(TileBackground(isOn: isOn))
                .contentShape(.rect(cornerRadius: Theme.tileRadius))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(title), \(isAvailable ? subtitle : "unavailable")")
            .accessibilityHint("Opens \(title) settings")

            IconCircle(
                systemImage: systemImage, isOn: isOn, onColor: onColor, onColorIsLight: onColorIsLight,
                tileIsOn: isOn, action: onToggle
            )
            .padding(9)
            .accessibilityLabel(iconActionLabel ?? (isOn ? "Turn \(title) off" : "Turn \(title) on"))
            .disabled(!isAvailable)
        }
        .frame(height: Theme.tileHeight)
        .opacity(isAvailable ? 1 : 0.5)
        .animation(Theme.spring, value: isOn)
    }
}

/// Round icon button with its own hover ring, so the two tap areas of a tile are clear.
struct IconCircle: View {
    let systemImage: String
    let isOn: Bool
    var onColor: Color = Theme.bulbYellow
    /// Light circle → dark symbol. The yellow bulb uses a white symbol.
    var onColorIsLight: Bool = false
    var tileIsOn: Bool = false
    var size: CGFloat = 34
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .semibold))
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(symbolColor)
                .frame(width: size, height: size)
                // A white symbol on a bright circle gets a faint shadow to stay crisp.
                .shadow(color: isOn && !onColorIsLight ? .black.opacity(0.22) : .clear, radius: 1, y: 0.5)
                .background(Circle().fill(isOn ? onColor : Color.primary.opacity(0.12)))
                .shadow(color: isOn ? onColor.opacity(0.75) : .clear, radius: 8)
                .overlay(
                    Circle()
                        .strokeBorder(ringColor, lineWidth: 1.5)
                        .padding(-3)
                        .opacity(hovering ? 1 : 0)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var symbolColor: Color {
        if isOn { return onColorIsLight ? Color.black.opacity(0.75) : .white }
        return .primary
    }

    private var ringColor: Color {
        tileIsOn ? Color.black.opacity(0.25) : Color.primary.opacity(0.35)
    }
}
