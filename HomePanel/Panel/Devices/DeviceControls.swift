import HAKit
import SwiftUI

/// A `GlassSlider` bound to a live HA value (0…1). While dragging, and briefly after release,
/// it shows your value so it doesn't jump back before HA confirms; changes are debounced.
struct LiveSlider: View {
    let value: Double
    var systemImage: String?
    var tint: Color = Theme.onFill
    let accessibilityName: String
    let label: (Double) -> String
    let commit: (Double) -> Void

    @State private var local = 0.0
    @State private var editing = false
    @State private var heldUntil = Date.distantPast
    @State private var debouncer = Debouncer()

    private var shown: Double { editing || Date.now < heldUntil ? local : value }

    var body: some View {
        GlassSlider(
            value: Binding(
                get: { shown },
                set: { newValue in
                    local = newValue
                    debouncer.call { [commit] in commit(newValue) }
                }),
            systemImage: systemImage,
            valueLabel: label(shown),
            tint: tint,
            accessibilityName: accessibilityName,
            onEditingChanged: { isEditing in
                if isEditing { local = value }
                editing = isEditing
                if !isEditing {
                    debouncer.flush()
                    heldUntil = .now.addingTimeInterval(1.5)
                }
            })
    }
}

/// A full-width row with a switch, for settings like "Oscillate" or "Mute".
struct ToggleRow: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                Capsule()
                    .fill(isOn ? Color.green : Color.primary.opacity(0.15))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(2).shadow(radius: 1)
                    }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(TileBackground(radius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.spring, value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A big round state button for locks and alarms.
struct StateDial: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var color: Color = .secondary
    var active = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(active ? color : Color.secondary)
                .frame(width: 104, height: 104)
                .background(Circle().fill(active ? color.opacity(0.18) : Color.primary.opacity(0.08)))
                .shadow(color: active ? color.opacity(0.5) : .clear, radius: 14)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Code entry for locks and alarms: a number pad for numeric codes, a secure field otherwise.
/// The code lives only in this view's state and is never saved or logged.
struct CodeEntry: View {
    let numeric: Bool
    @Binding var code: String

    var body: some View {
        VStack(spacing: 10) {
            if numeric {
                HStack(spacing: 8) {
                    ForEach(0..<max(4, code.count), id: \.self) { i in
                        Circle()
                            .fill(i < code.count ? Color.primary : Color.primary.opacity(0.15))
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(height: 14)
                .accessibilityLabel("Code, \(code.count) digits entered")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "clear", "0", "delete"], id: \.self) { key in
                        keyButton(key)
                    }
                }
            } else {
                SecureField("Code", text: $code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(TileBackground(radius: 10))
            }
        }
    }

    @ViewBuilder private func keyButton(_ key: String) -> some View {
        Button {
            switch key {
            case "clear": code = ""
            case "delete": if !code.isEmpty { code.removeLast() }
            default: if code.count < 12 { code.append(key) }
            }
        } label: {
            Group {
                switch key {
                case "clear": Text("Clear").font(.system(size: 12, weight: .medium))
                case "delete": Image(systemName: "delete.left").font(.system(size: 15, weight: .medium))
                default: Text(key).font(.system(size: 20, weight: .medium, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(key == "delete" ? "Delete" : key == "clear" ? "Clear" : key)
    }
}

/// "On since 14:02" / "Changed Tue 09:12".
enum SinceText {
    static func text(_ prefix: String, _ date: Date) -> String? {
        guard date > .distantPast else { return nil }
        let when = date.formatted(
            date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
        return "\(prefix) \(when)"
    }
}
