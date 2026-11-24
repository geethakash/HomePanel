import HAKit
import SwiftUI

/// The list of rooms that replaces the sections when the room name is tapped.
/// ⌘1–⌘9 switch rooms from anywhere in the panel (see `RoomShortcuts`).
struct RoomList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let rooms = app.config.config.rooms
        let current = app.currentRoom?.id
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Rooms")
            VStack(spacing: 2) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    RoomRow(room: room, index: index, isCurrent: room.id == current) {
                        app.selectRoom(room.id)
                    }
                }
            }
            .padding(4)
            .background(TileBackground(radius: 14))

            Button {
                app.settingsTab = "rooms"
                NSApp.activate()
                openSettings()
            } label: {
                Label("Edit rooms in Settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }
}

private struct RoomRow: View {
    @Environment(AppModel.self) private var app
    let room: Room
    let index: Int
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: room.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.onText : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isCurrent ? AnyShapeStyle(Theme.onFill) : AnyShapeStyle(Color.primary.opacity(0.1))))
                VStack(alignment: .leading, spacing: 1) {
                    Text(room.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .opacity(isCurrent ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .accessibilityLabel(room.name)
        .accessibilityValue(isCurrent ? "Current room" : "")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// "6 devices" (cards that aren't hidden).
    private var summary: String {
        let count = room.sections.reduce(0) { $0 + $1.visibleCards.count }
        return count == 1 ? "1 device" : "\(count) devices"
    }
}

/// Invisible buttons that give ⌘1–⌘9 to the first nine rooms.
struct RoomShortcuts: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let rooms = app.config.config.rooms.prefix(9)
        ZStack {
            ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                Button("") { app.selectRoom(room.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
