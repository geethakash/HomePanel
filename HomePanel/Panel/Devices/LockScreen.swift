import HAKit
import SwiftUI

/// Locks: locking is one tap; unlocking and opening need a second tap within a few seconds,
/// and a code when the lock has one.
struct LockScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    @State private var code = ""
    @State private var armed: String?  // "unlock" or "open" after the first tap
    @State private var disarmTask: Task<Void, Never>?

    var body: some View {
        let lock = app.store[card.entityID]
        let name = app.displayName(card)
        let state = lock?.state ?? "unavailable"
        let locked = state == "locked"
        let needsCode = lock?.codeFormat != nil

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(name)

            StateDial(
                systemImage: locked ? "lock.fill" : (state == "jammed" ? "exclamationmark.lock.fill" : "lock.open.fill"),
                title: lock.map(DeviceText.summary) ?? "Unavailable",
                subtitle: lock?.changedBy.map { "By \($0)" } ?? lock.flatMap { SinceText.text("Since", $0.lastChanged) },
                color: state == "jammed" ? Color(hex: 0xFF453A) : Theme.amber,
                active: lock?.isAvailable == true && !locked)

            if needsCode {
                CodeEntry(numeric: Self.isNumeric(lock?.codeFormat), code: $code)
            }

            VStack(spacing: 8) {
                if locked || state == "jammed" {
                    confirmButton("unlock", title: "Unlock", systemImage: "lock.open")
                } else {
                    CapsuleButton(title: "Lock", systemImage: "lock") { send("lock") }
                }
                if lock?.lockFeatures.contains(.open) == true {
                    confirmButton("open", title: "Open door", systemImage: "door.left.hand.open")
                }
            }
            .disabled(lock?.isAvailable != true || (needsCode && code.isEmpty))
        }
        .onDisappear {
            code = ""
            disarmTask?.cancel()
        }
    }

    /// First tap arms it ("Tap again to unlock"), a second tap within 4 s sends it.
    private func confirmButton(_ service: String, title: String, systemImage: String) -> some View {
        let isArmed = armed == service
        return Button {
            if isArmed {
                armed = nil
                send(service)
            } else {
                withAnimation(Theme.spring) { armed = service }
                disarmTask?.cancel()
                disarmTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    withAnimation(Theme.spring) { armed = nil }
                }
            }
        } label: {
            Label(isArmed ? "Tap again to \(title.lowercased())" : title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isArmed ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(isArmed ? Color(hex: 0xFF453A) : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(isArmed ? "Press again to confirm" : "Press twice to confirm")
    }

    private func send(_ service: String) {
        var data: [String: JSONValue] = [:]
        if !code.isEmpty { data["code"] = .string(code) }
        app.call("lock", service, [card.entityID], data)
        code = ""
    }

    static func isNumeric(_ format: String?) -> Bool {
        guard let format else { return false }
        return format == "number" || format.contains("\\d") || format.contains("[0-9]")
    }
}
