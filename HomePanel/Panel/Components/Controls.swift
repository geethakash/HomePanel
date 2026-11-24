import SwiftUI

struct PillOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

/// Segmented pill: the selected segment is near-white.
struct SegmentedPills: View {
    let options: [PillOption]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selected
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Theme.onText : Color.primary)
                        .background(Capsule().fill(isSelected ? Theme.onFill : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .animation(Theme.spring, value: selected)
    }
}

/// Wrapping row of pills (presets etc.).
struct PillFlow: View {
    let options: [PillOption]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options) { option in
                let isSelected = option.value == selected
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Theme.onText : Color.primary)
                        .background(Capsule().fill(isSelected ? Theme.onFill : Color.primary.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Simple left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Large capsule slider (0…1) with an icon on the left and a value on the right.
struct GlassSlider: View {
    @Binding var value: Double
    var systemImage: String?
    var valueLabel: String
    var tint: Color = Theme.onFill
    var height: CGFloat = 38
    var accessibilityName: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(height, geo.size.width * value)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: width)
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.65))
                    }
                    Spacer()
                    Text(valueLabel)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(value > 0.85 ? Theme.onText : Color.primary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 13)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        value = min(1, max(0, g.location.x / geo.size.width))
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(valueLabel)
        .accessibilityAdjustableAction { direction in
            onEditingChanged(true)
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }
}

/// Round power button (white when on).
struct PowerButton: View {
    let isOn: Bool
    var label: String = "Power"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isOn ? Theme.onText : Color.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? Theme.onFill : Color.primary.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isOn ? "Turn \(label) off" : "Turn \(label) on")
        .animation(Theme.spring, value: isOn)
    }
}

/// Wide capsule action button ("All on", "All off").
struct CapsuleButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Back chevron plus title, with optional trailing content.
struct BackHeader<Trailing: View>: View {
    @Environment(AppModel.self) private var app
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Button {
                app.pop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Back")
            .accessibilityValue(title)
            Spacer()
            trailing
        }
        .frame(minHeight: 32)
    }
}

/// A selectable row in a grouped list (near-white with a checkmark when selected).
struct OptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? Theme.onText : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.onFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Segmented pills when the options fit on one line, a wrapping flow of pills when there are many.
struct ChoicePills: View {
    let options: [PillOption]
    let selected: String?
    var maxSegments = 5
    let onSelect: (String) -> Void

    var body: some View {
        if options.count <= maxSegments {
            SegmentedPills(options: options, selected: selected, onSelect: onSelect)
        } else {
            PillFlow(options: options, selected: selected, onSelect: onSelect)
        }
    }
}
