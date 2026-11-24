import HAKit
import SwiftUI

/// The Rooms tab: rooms on the left, the selected room's sections and cards on the right.
/// Every change is saved right away and shows in the panel.
struct RoomsEditor: View {
    @Environment(AppModel.self) private var app
    @State private var selection: UUID?
    @State private var showingAreaPicker = false
    @State private var confirmDelete: Room?

    var body: some View {
        let rooms = app.config.config.rooms
        // A plain sidebar + detail. NavigationSplitView would take over the window toolbar,
        // which is where the Settings tabs live, and the tabs would stop responding.
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(rooms) { room in
                        Label(room.name.isEmpty ? "Untitled" : room.name, systemImage: room.icon)
                            .tag(room.id)
                            .contextMenu {
                                Button("Delete Room…", role: .destructive) { confirmDelete = room }
                            }
                    }
                    .onMove { from, to in app.config.update { $0.rooms.move(fromOffsets: from, toOffset: to) } }
                }
                .listStyle(.sidebar)
                Divider()
                sidebarFooter
            }
            .frame(width: 210)

            Divider()

            Group {
                if let id = selection, let room = ConfigBindings.room(app.config, id) {
                    RoomDetail(room: room)
                        .id(id)
                } else {
                    ContentUnavailableView(
                        rooms.isEmpty ? "No rooms yet" : "Select a room",
                        systemImage: "square.grid.2x2",
                        description: Text(
                            rooms.isEmpty ? "Add rooms from your Home Assistant Areas, or start an empty one." : ""))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 580)
        .onAppear { selection = selection ?? app.currentRoom?.id }
        .sheet(isPresented: $showingAreaPicker) {
            AreaPicker(onDone: { showingAreaPicker = false })
                .frame(width: 460, height: 460)
        }
        .confirmationDialog(
            "Delete \(confirmDelete?.name ?? "room")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            presenting: confirmDelete
        ) { room in
            Button("Delete Room", role: .destructive) { delete(room) }
        } message: { room in
            Text("Its \(room.sections.reduce(0) { $0 + $1.cards.count }) cards are removed from the panel. Your Home Assistant isn't changed.")
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 2) {
            Menu {
                Button("From Home Assistant Areas…") { showingAreaPicker = true }
                    .disabled(app.catalog == nil)
                Button("Empty Room") {
                    let room = Room(name: "New Room")
                    app.config.update {
                        $0.rooms.append(room)
                        if $0.lastRoomID == nil { $0.lastRoomID = room.id }
                    }
                    selection = room.id
                }
            } label: {
                Image(systemName: "plus").frame(width: 22, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add a room")

            Button {
                if let id = selection, let room = app.config.config.room(id), room.id == id { confirmDelete = room }
            } label: {
                Image(systemName: "minus").frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Delete the selected room")

            Spacer()
            CatalogStatus()
        }
        .padding(8)
    }

    private func delete(_ room: Room) {
        app.config.update { config in
            config.rooms.removeAll { $0.id == room.id }
            if config.lastRoomID == room.id { config.lastRoomID = config.rooms.first?.id }
        }
        if selection == room.id { selection = app.config.config.rooms.first?.id }
        confirmDelete = nil
    }
}

/// "Connected" or a spinner while the Home Assistant catalog loads, with a refresh button.
struct CatalogStatus: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            if app.catalog == nil {
                if app.store.status == .connected || app.store.status == .connecting {
                    ProgressView().controlSize(.mini)
                }
                Text(app.store.status == .connected ? "Reading HA…" : app.store.status.label)
                    .lineLimit(1)
            } else {
                Button {
                    Task { await app.loadCatalog(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload areas and devices from Home Assistant")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Bindings into the saved layout: reads come from the store, writes go through `update`.
@MainActor
enum ConfigBindings {
    static func room(_ store: ConfigStore, _ id: UUID) -> Binding<Room>? {
        guard let initial = store.config.rooms.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.config.rooms.first { $0.id == id } ?? initial },
            set: { new in
                store.update { config in
                    if let i = config.rooms.firstIndex(where: { $0.id == id }) { config.rooms[i] = new }
                }
            })
    }
}
