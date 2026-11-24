import HAKit
import SwiftUI

/// Search everything in Home Assistant and add devices to a section.
struct AddDeviceSheet: View {
    @Environment(AppModel.self) private var app
    @Binding var room: Room
    let sectionID: UUID
    let onDone: () -> Void

    @State private var query = ""
    @State private var area = "*"  // "*" = any, "" = no area
    @State private var kind: Card.Kind?
    @State private var showAll = false

    var body: some View {
        let inRoom = Set(room.sections.flatMap(\.cards).map(\.entityID))
        let results = filtered()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search devices", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Area", selection: $area) {
                    Text("Any area").tag("*")
                    ForEach(app.catalog?.areas ?? []) { Text($0.name).tag($0.id) }
                    Text("No area").tag("")
                }
                .labelsHidden()
                .fixedSize()
                Picker("Type", selection: $kind) {
                    Text("Any type").tag(Card.Kind?.none)
                    ForEach(Card.Kind.allCases, id: \.self) { Text(KindName.name($0)).tag(Card.Kind?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(12)

            List(results) { entity in
                HStack(spacing: 10) {
                    Image(systemName: Card.Kind.forEntity(entity.entityID).defaultIcon)
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entity.name)
                        Text([entity.entityID, entity.areaID.flatMap { app.catalog?.area($0)?.name }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if inRoom.contains(entity.entityID) {
                        Label("Added", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Add") { add(entity) }
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            HStack {
                Toggle("Include settings and diagnostic entities", isOn: $showAll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Text("\(results.count) shown").font(.caption).foregroundStyle(.secondary)
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private func filtered() -> [CatalogEntity] {
        guard let catalog = app.catalog else { return [] }
        let areaFilter: String?? = area == "*" ? nil : .some(area.isEmpty ? nil : area)
        return catalog.search(query, primaryOnly: !showAll).filter { e in
            if let areaFilter, e.areaID != areaFilter { return false }
            if let kind, Card.Kind.forEntity(e.entityID) != kind { return false }
            return !LayoutGenerator.skippedDomains.contains(e.domain) || ["select", "number"].contains(e.domain)
        }
    }

    private func add(_ entity: CatalogEntity) {
        guard let catalog = app.catalog, let i = room.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        room.sections[i].cards.append(LayoutGenerator.card(for: entity.entityID, in: catalog))
    }
}

/// Plain names for card kinds in pickers.
enum KindName {
    static func name(_ kind: Card.Kind) -> String {
        switch kind {
        case .toggle: "Switch"
        case .light: "Light"
        case .climate: "Climate"
        case .cover: "Cover"
        case .fan: "Fan"
        case .media: "Media player"
        case .lock: "Lock"
        case .alarm: "Alarm"
        case .sensor: "Sensor"
        case .binarySensor: "Binary sensor"
        case .scene: "Scene"
        case .script: "Script"
        case .button: "Button"
        case .select: "Select"
        case .number: "Number"
        }
    }

    static func role(_ role: Attachment.Role) -> String {
        switch role {
        case .preset: "Preset (light)"
        case .speed: "Effect speed (light)"
        case .fanSpeed: "Fan speed (climate)"
        case .swingVertical: "Up-down air flow (climate)"
        case .swingHorizontal: "Left-right air flow (climate)"
        case .sleep: "Sleep mode (climate)"
        case .powerLimit: "Power limit (climate)"
        case .feature: "Feature switch (climate)"
        case .offTimer: "Turn-off timer (switch)"
        case .powerOnBehaviour: "Power-on behaviour (switch)"
        case .generic: "Other"
        }
    }
}
