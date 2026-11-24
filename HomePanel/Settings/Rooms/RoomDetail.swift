import HAKit
import SwiftUI

/// One room: name, icon, header readings, and its sections of cards.
struct RoomDetail: View {
    @Environment(AppModel.self) private var app
    @Binding var room: Room

    @State private var addingTo: UUID?  // section receiving new devices
    @State private var inspecting: CardRef?
    @State private var confirmRebuild = false

    struct CardRef: Identifiable, Hashable {
        let section: UUID
        let card: UUID
        var id: UUID { card }
    }

    static let icons = [
        "house", "sofa", "bed.double", "fork.knife", "shower", "desktopcomputer", "car", "leaf", "washer",
        "door.left.hand.closed", "teddybear", "dumbbell", "tv", "person.2", "books.vertical", "lightbulb.2",
        "sun.max", "moon", "stairs", "building.2", "tree", "gamecontroller", "music.note", "testtube.2",
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $room.name)
                Picker("Icon", selection: $room.icon) {
                    ForEach(Self.icons + (Self.icons.contains(room.icon) ? [] : [room.icon]), id: \.self) { icon in
                        Label(icon, systemImage: icon).labelStyle(.iconOnly).tag(icon)
                    }
                }
                headerSensorPicker(0, title: "Header reading")
                headerSensorPicker(1, title: "Second reading")
                if let areaID = room.areaID {
                    LabeledContent("Home Assistant Area") {
                        HStack {
                            Text(app.catalog?.area(areaID)?.name ?? areaID).foregroundStyle(.secondary)
                            Button("Rebuild…") { confirmRebuild = true }
                                .disabled(app.catalog == nil)
                        }
                    }
                }
            } header: {
                Text("Room")
            }

            ForEach($room.sections) { $section in
                SectionEditor(
                    section: $section,
                    canMoveUp: section.id != room.sections.first?.id,
                    canMoveDown: section.id != room.sections.last?.id,
                    onAdd: { addingTo = section.id },
                    onInspect: { inspecting = CardRef(section: section.id, card: $0) },
                    onMove: { moveSection(section.id, by: $0) },
                    onDelete: { room.sections.removeAll { $0.id == section.id } })
            }

            Section {
                Button("Add Section") {
                    room.sections.append(CardSection(title: "New Section"))
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $addingTo) { sectionID in
            AddDeviceSheet(room: $room, sectionID: sectionID) { addingTo = nil }
                .frame(width: 560, height: 520)
        }
        .sheet(item: $inspecting) { ref in
            if let binding = cardBinding(ref) {
                CardInspector(card: binding, room: $room, sectionID: ref.section) { inspecting = nil }
                    .frame(width: 520, height: 560)
            }
        }
        .confirmationDialog("Rebuild \(room.name) from Home Assistant?", isPresented: $confirmRebuild) {
            Button("Rebuild", role: .destructive) { rebuild() }
        } message: {
            Text("Sections and cards are replaced with what's in the area now. Names, icons and order you changed are lost.")
        }
    }

    private func headerSensorPicker(_ index: Int, title: String) -> some View {
        let sensors = (app.catalog?.entities ?? []).filter {
            $0.domain == "sensor" && app.catalog?.states[$0.entityID]?.numericState != nil
        }
        let current = room.headerSensors.indices.contains(index) ? room.headerSensors[index] : ""
        return Picker(title, selection: Binding(
            get: { current },
            set: { new in
                var list = room.headerSensors
                while list.count <= index { list.append("") }
                list[index] = new
                room.headerSensors = list.filter { !$0.isEmpty }
            })
        ) {
            Text("None").tag("")
            if !current.isEmpty, !sensors.contains(where: { $0.entityID == current }) {
                Text(current).tag(current)
            }
            ForEach(sensors) { sensor in
                Text(sensor.name).tag(sensor.entityID)
            }
        }
        .disabled(index == 1 && room.headerSensors.isEmpty)
    }

    private func moveSection(_ id: UUID, by offset: Int) {
        guard let i = room.sections.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard room.sections.indices.contains(j) else { return }
        room.sections.swapAt(i, j)
    }

    private func cardBinding(_ ref: CardRef) -> Binding<Card>? {
        guard let s = room.sections.firstIndex(where: { $0.id == ref.section }),
            let c = room.sections[s].cards.firstIndex(where: { $0.id == ref.card })
        else { return nil }
        let initial = room.sections[s].cards[c]
        return Binding(
            get: {
                room.sections.first { $0.id == ref.section }?.cards.first { $0.id == ref.card } ?? initial
            },
            set: { new in
                guard let s = room.sections.firstIndex(where: { $0.id == ref.section }),
                    let c = room.sections[s].cards.firstIndex(where: { $0.id == ref.card })
                else { return }
                room.sections[s].cards[c] = new
            })
    }

    private func rebuild() {
        guard let catalog = app.catalog else { return }
        let fresh = LayoutGenerator.room(for: room.areaID, in: catalog)
        room.sections = fresh.sections
        if room.headerSensors.isEmpty { room.headerSensors = fresh.headerSensors }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// One section: title, style, and its cards (drag to reorder, eye to hide, click to edit).
private struct SectionEditor: View {
    @Environment(AppModel.self) private var app
    @Binding var section: CardSection
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onAdd: () -> Void
    let onInspect: (UUID) -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        Section {
            ForEach(section.cards) { card in
                CardRow(card: card, onToggleHidden: {
                    if let i = section.cards.firstIndex(where: { $0.id == card.id }) { section.cards[i].hidden.toggle() }
                }, onEdit: { onInspect(card.id) }, onRemove: {
                    section.cards.removeAll { $0.id == card.id }
                })
            }
            .onMove { section.cards.move(fromOffsets: $0, toOffset: $1) }

            Button {
                onAdd()
            } label: {
                Label("Add Device…", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(app.catalog == nil)
        } header: {
            HStack {
                TextField("Section title", text: $section.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                Spacer()
                Picker("Style", selection: $section.style) {
                    Text("Tiles").tag(CardSection.Style.grid)
                    Text("Rows").tag(CardSection.Style.rows)
                    Text("Pills").tag(CardSection.Style.pills)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Menu {
                    Button("Move Up") { onMove(-1) }.disabled(!canMoveUp)
                    Button("Move Down") { onMove(1) }.disabled(!canMoveDown)
                    Divider()
                    Button("Delete Section…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .confirmationDialog("Delete \(section.title)?", isPresented: $confirmDelete) {
            Button("Delete Section", role: .destructive, action: onDelete)
        } message: {
            Text("Its \(section.cards.count) cards are removed from the panel.")
        }
    }
}

private struct CardRow: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let onToggleHidden: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: card.displayIcon)
                .frame(width: 22)
                .foregroundStyle(card.hidden ? .tertiary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.editorName(card))
                    .foregroundStyle(card.hidden ? .secondary : .primary)
                Text(card.entityID + (card.attachments.isEmpty ? "" : " · +\(card.attachments.count) related"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if app.catalog != nil, app.catalog?.entity(card.entityID) == nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Home Assistant doesn't have this entity")
            }
            Button(action: onToggleHidden) {
                Image(systemName: card.hidden ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(card.hidden ? "Show in the panel" : "Hide from the panel")
            Button("Edit…", action: onEdit)
                .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button(card.hidden ? "Show" : "Hide", action: onToggleHidden)
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}

extension AppModel {
    /// A card's name for the editor: its own name, HA's name, or the entity ID.
    func editorName(_ card: Card) -> String {
        card.name ?? catalog?.entity(card.entityID)?.name ?? store[card.entityID]?.friendlyName ?? card.entityID
    }
}
