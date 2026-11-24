import HAKit
import SwiftUI

extension View {
    /// In edit mode: wiggle, an eye button to hide or show, drag to reorder, and a menu to nudge.
    func editable(_ card: Card, index: Int, editing: Bool) -> some View {
        modifier(EditableTile(card: card, index: index, editing: editing))
    }
}

private struct EditableTile: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: Card
    let index: Int
    let editing: Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        if editing {
            let name = app.displayName(card)
            content
                .allowsHitTesting(false)
                .opacity(card.hidden ? 0.38 : 1)
                // A clear layer over the tile takes the drag (the tile's own buttons are off).
                .overlay {
                    Color.white.opacity(0.001)
                        .contentShape(Rectangle())
                        .draggable(card.id.uuidString) {
                            Label(name, systemImage: card.displayIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.regularMaterial))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(targeted ? 1 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        app.toggleHidden(card.id)
                    } label: {
                        Image(systemName: card.hidden ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(card.hidden ? Color.white : Theme.onText)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(card.hidden ? Color.gray : Theme.onFill))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .offset(x: 6, y: -6)
                    .accessibilityLabel(card.hidden ? "Show \(name)" : "Hide \(name)")
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    app.moveCard(id, before: card.id)
                    return true
                } isTargeted: { targeted = $0 }
                .modifier(Wiggle(active: !reduceMotion, seed: index))
                .contextMenu {
                    Button("Move Earlier") { app.nudgeCard(card.id, by: -1) }
                    Button("Move Later") { app.nudgeCard(card.id, by: 1) }
                    Divider()
                    Button(card.hidden ? "Show" : "Hide") { app.toggleHidden(card.id) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(name)\(card.hidden ? ", hidden" : "")")
                .accessibilityAction(named: "Move earlier") { app.nudgeCard(card.id, by: -1) }
                .accessibilityAction(named: "Move later") { app.nudgeCard(card.id, by: 1) }
                .accessibilityAction(named: card.hidden ? "Show" : "Hide") { app.toggleHidden(card.id) }
        } else {
            content
        }
    }
}

/// A small, slightly out-of-step rotation, like Home Screen icons in jiggle mode.
private struct Wiggle: ViewModifier {
    let active: Bool
    let seed: Int
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (phase ? 0.9 : -0.9) : 0))
            .onAppear {
                guard active else { return }
                let duration = 0.13 + Double(seed % 3) * 0.012
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(Double(seed % 4) * 0.03)) {
                    phase = true
                }
            }
    }
}
