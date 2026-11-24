import HAKit
import SwiftUI

/// Edit one card: name, icon, type, visibility, section, and its related entities.
struct CardInspector: View {
    @Environment(AppModel.self) private var app
    @Binding var card: Card
    @Binding var room: Room
    let sectionID: UUID
    let onDone: () -> Void

    @State private var newAttachmentID = ""
    @State private var confirmRemove = false

    var body: some View {
        let haName = app.catalog?.entity(card.entityID)?.name ?? app.store[card.entityID]?.friendlyName
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Entity", value: card.entityID)
                    TextField("Name", text: Binding(
                        get: { card.name ?? "" },
                        set: { card.name = $0.isEmpty ? nil : $0 }),
                        prompt: Text(haName ?? card.entityID))
                    LabeledContent("Icon") {
                        HStack {
                            Image(systemName: card.displayIcon).frame(width: 22)
                            TextField("Icon", text: Binding(
                                get: { card.icon ?? "" },
                                set: { card.icon = $0.isEmpty ? nil : $0 }),
                                prompt: Text(card.kind.defaultIcon))
                                .labelsHidden()
                        }
                    }
                    Picker("Type", selection: $card.kind) {
                        ForEach(Card.Kind.allCases, id: \.self) { Text(KindName.name($0)).tag($0) }
                    }
                    Toggle("Hidden from the panel", isOn: $card.hidden)
                    Picker("Section", selection: Binding(get: { sectionID }, set: { move(to: $0) })) {
                        ForEach(room.sections) { Text($0.title.isEmpty ? "Untitled" : $0.title).tag($0.id) }
                    }
                } footer: {
                    Text("The icon is an SF Symbol name, like lightbulb or fan. Leave it empty for the default.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach($card.attachments, id: \.entityID) { $attachment in
                        AttachmentRow(attachment: $attachment) {
                            card.attachments.removeAll { $0.entityID == attachment.entityID }
                        }
                    }
                    HStack {
                        Picker("Add", selection: $newAttachmentID) {
                            Text("Choose an entity…").tag("")
                            ForEach(candidates(), id: \.entityID) { e in
                                Text("\(e.name) (\(e.entityID))").tag(e.entityID)
                            }
                        }
                        Button("Add") {
                            card.attachments.append(Attachment(newAttachmentID, role: suggestedRole(newAttachmentID)))
                            newAttachmentID = ""
                        }
                        .disabled(newAttachmentID.isEmpty)
                    }
                } header: {
                    Text("Related entities")
                } footer: {
                    Text("Shown on the device screen, e.g. a light's preset select or an A/C's air-flow selects. Entities from the same device are listed first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Remove Card…", role: .destructive) { confirmRemove = true }
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .confirmationDialog("Remove \(app.editorName(card)) from \(room.name)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                let id = card.id
                onDone()
                for i in room.sections.indices { room.sections[i].cards.removeAll { $0.id == id } }
            }
        }
    }

    /// Same-device entities first, then every select, number, switch and timer.
    private func candidates() -> [CatalogEntity] {
        guard let catalog = app.catalog else { return [] }
        let attached = Set(card.attachments.map(\.entityID) + [card.entityID])
        let device = catalog.entity(card.entityID)?.deviceID
        let sameDevice = device.map { catalog.entities(ofDevice: $0) } ?? []
        let others = catalog.entities.filter {
            ["select", "number", "switch", "timer", "input_select", "input_number", "input_boolean"].contains($0.domain)
                && $0.deviceID != device
        }
        return (sameDevice + others).filter { !attached.contains($0.entityID) }
    }

    private func suggestedRole(_ entityID: String) -> Attachment.Role {
        let w = ((app.catalog?.entity(entityID)?.name ?? "") + " " + entityID).lowercased()
        let domain = String(entityID.prefix { $0 != "." })
        switch card.kind {
        case .light:
            if domain == "select" && w.contains("preset") { return .preset }
            if domain == "number" && w.contains("speed") { return .speed }
        case .climate:
            if domain == "select", let role = LayoutGenerator.climateSelectRole(w.replacingOccurrences(of: "_", with: " ")) {
                return role
            }
            if domain == "switch" { return .feature }
        case .toggle:
            if domain == "timer" { return .offTimer }
            if domain == "select" { return .powerOnBehaviour }
        default: break
        }
        return .generic
    }

    private func move(to newSection: UUID) {
        guard newSection != sectionID,
            let from = room.sections.firstIndex(where: { $0.id == sectionID }),
            let to = room.sections.firstIndex(where: { $0.id == newSection })
        else { return }
        let moving = card
        onDone()
        room.sections[from].cards.removeAll { $0.id == moving.id }
        room.sections[to].cards.append(moving)
    }
}

private struct AttachmentRow: View {
    @Environment(AppModel.self) private var app
    @Binding var attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.catalog?.entity(attachment.entityID)?.name ?? attachment.entityID)
                    .lineLimit(1)
                Spacer()
                Button(role: .destructive, action: onRemove) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove")
            }
            HStack {
                Picker("Role", selection: $attachment.role) {
                    ForEach(Attachment.Role.allCases, id: \.self) { Text(KindName.role($0)).tag($0) }
                }
                .labelsHidden()
                TextField("Label", text: Binding(
                    get: { attachment.name ?? "" },
                    set: { attachment.name = $0.isEmpty ? nil : $0 }),
                    prompt: Text("Label (optional)"))
                    .labelsHidden()
                    .frame(width: 130)
            }
            .font(.caption)
        }
    }
}
