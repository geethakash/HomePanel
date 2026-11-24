import AppKit
import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 344
    static let panelMaxHeight: CGFloat = 900
    static let panelRadius: CGFloat = 26
    static let padding: CGFloat = 14
    static let tileRadius: CGFloat = 18
    static let tileHeight: CGFloat = 92
    static let gridSpacing: CGFloat = 8

    /// Control Center style "on" tile: near-white on dark glass, pure white on light glass.
    static let onFill = adaptive(dark: NSColor(white: 1, alpha: 0.94), light: .white)
    /// Slider and toggle tracks, and other "empty" fills.
    static let track = adaptive(dark: NSColor(white: 1, alpha: 0.10), light: NSColor(white: 0, alpha: 0.11))
    /// Hairline borders on tiles and cards.
    static let hairline = adaptive(dark: NSColor(white: 1, alpha: 0.12), light: NSColor(white: 0, alpha: 0.07))
    /// Lifts "on" surfaces off light glass; nothing on dark, where they already stand out.
    static let onShadow = adaptive(dark: .clear, light: NSColor(white: 0, alpha: 0.16))

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let onText = Color.black.opacity(0.88)
    static let onSecondaryText = Color.black.opacity(0.5)
    static let bulbYellow = Color(hex: 0xFFD60A)
    static let amber = Color(hex: 0xFF9F0A)

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }

    init(rgb: [Int]) {
        let c = rgb + [0, 0, 0]
        self.init(.sRGB, red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255)
    }
}

enum RGB {
    /// Relative luminance 0…1 (for picking a readable symbol color on a colored circle).
    static func luminance(_ rgb: [Int]) -> Double {
        guard rgb.count >= 3 else { return 0 }
        return (0.2126 * Double(rgb[0]) + 0.7152 * Double(rgb[1]) + 0.0722 * Double(rgb[2])) / 255
    }

    static func distance(_ a: [Int], _ b: [Int]) -> Double {
        guard a.count >= 3, b.count >= 3 else { return .infinity }
        return sqrt((0..<3).reduce(0.0) { $0 + pow(Double(a[$1] - b[$1]), 2) })
    }
}

/// Section title: 12 pt semibold, uppercase, secondary.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled block of the panel.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title)
            content
        }
    }
}

/// Background for tiles and rows: near-white when on, translucent otherwise.
struct TileBackground: View {
    var isOn: Bool = false
    var radius: CGFloat = Theme.tileRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(isOn ? AnyShapeStyle(Theme.onFill) : AnyShapeStyle(Color.primary.opacity(0.08)))
            .shadow(color: isOn ? Theme.onShadow : .clear, radius: 5, y: 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(isOn ? 0 : 1), lineWidth: 0.5)
            )
    }
}

/// Slight press-down scale for custom buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Shakes the view when HA didn't confirm an optimistic change for `entityID`.
struct RollbackShake: ViewModifier {
    @Environment(AppModel.self) private var app
    let entityID: String
    @State private var shakes = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: shakes) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    for x in [-6.0, 6, -4, 4, -2, 0] { LinearKeyframe(x, duration: 0.05) }
                }
            }
            .onChange(of: app.store.rolledBack.contains(entityID)) { _, failed in
                guard failed else { return }
                shakes += 1
                app.store.acknowledgeRollback(entityID)
            }
    }
}

extension View {
    func rollbackShake(_ entityID: String) -> some View { modifier(RollbackShake(entityID: entityID)) }
}

enum SFSymbol {
    /// The ".fill" variant of a symbol if it exists, otherwise the symbol itself.
    static func filled(_ name: String) -> String {
        let fill = name + ".fill"
        return NSImage(systemSymbolName: fill, accessibilityDescription: nil) != nil ? fill : name
    }
}
