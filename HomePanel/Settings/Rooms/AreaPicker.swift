import HAKit
import SwiftUI

/// Pick Home Assistant Areas to turn into rooms (used by setup and the Rooms tab).
struct AreaPicker: View {
    @Environment(AppModel.self) private var app
    var addLabel = "Add Rooms"
    let onDone: () -> Void

    /// Area IDs; "" stands for devices without an area.
    @State private var chosen: Set<String> = []
    @State private var initialised = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose rooms from Home Assistant")
                .font(.headline)
            Text("Each Area becomes a room with its lights, switches, climate, media and more. You can change everything afterwards.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let catalog = app.catalog {
                let counts = catalog.primaryCountByArea
                let used = Set(app.config.config.rooms.compactMap(\.areaID))
                List {
                    ForEach(catalog.areas) { area in
                        row(id: area.id, name: area.name, icon: LayoutGenerator.icon(for: area),
                            count: counts[area.id] ?? 0, alreadyRoom: used.contains(area.id))
                    }
                    if let unassigned = counts[nil], unassigned > 0 {
                        row(id: "", name: "Devices without an area", icon: "questionmark.square.dashed",
                            count: unassigned, alreadyRoom: false)
                    }
                }
                .onAppear {
                    guard !initialised else { return }
                    initialised = true
                    chosen = Set(catalog.areas.filter { (counts[$0.id] ?? 0) > 0 && !used.contains($0.id) }.map(\.id))
                }
                if catalog.areas.isEmpty {
                    Text("Your Home Assistant has no Areas yet. Add rooms by hand in the Rooms tab, or create Areas in Home Assistant → Settings → Areas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(app.store.status == .connected ? "Reading your Home Assistant…" : app.store.status.label)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Cancel", action: onDone)
                Spacer()
                Button(chosen.isEmpty ? addLabel : "\(addLabel) (\(chosen.count))") {
                    app.addRooms(forAreas: chosen.sorted().map { $0.isEmpty ? nil : $0 })
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty || app.catalog == nil)
            }
        }
        .padding(20)
    }

    private func row(id: String, name: String, icon: String, count: Int, alreadyRoom: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(id) },
            set: { if $0 { chosen.insert(id) } else { chosen.remove(id) } })
        ) {
            HStack {
                Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
                Text(name)
                Spacer()
                Text(alreadyRoom ? "Already a room · \(count)" : "\(count) devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(count == 0)
    }
}
