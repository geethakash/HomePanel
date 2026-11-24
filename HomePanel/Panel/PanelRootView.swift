import AppKit
import HAKit
import SwiftUI

/// The single panel under the menu bar icon. Screens push and pop inside it with a slide.
///
/// Navigation is a small custom stack (`AppModel.path`) instead of `NavigationStack`, so the
/// panel can size itself to its content and use our own chevron header.
struct PanelRootView: View {
    @Environment(AppModel.self) private var app
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        ScrollView(.vertical) {
            ZStack(alignment: .top) {
                screen(for: app.path.last)
                    .id(app.path.last)
                    .transition(.push(from: app.navDirection == .forward ? .trailing : .leading))
            }
            .padding(Theme.padding)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
        .frame(width: Theme.panelWidth, height: min(max(contentHeight, 120), Theme.panelMaxHeight))
        // The MenuBarExtra window already draws the Liquid Glass background, rounded corners
        // and hairline border on macOS 26, so no extra glass or border here (it doubled up).
        .overlay(alignment: .bottom) { ErrorToast() }
        .onKeyPress(.escape) {
            // Back out one level; at the top, let the system close the panel.
            if app.editing {
                app.setEditing(false)
            } else if app.showingRooms {
                withAnimation(Theme.spring) { app.showingRooms = false }
            } else if !app.path.isEmpty {
                app.pop()
            } else {
                return .ignored
            }
            return .handled
        }
        .background(RoomShortcuts())
        .background(WindowVisibilityReader { app.panelVisibilityChanged($0) })
    }

    @ViewBuilder
    private func screen(for route: Route?) -> some View {
        switch route {
        case nil:
            HomeScreen()
        case .card(let id):
            if let (section, card) = app.locate(id) {
                switch card.kind {
                case .light: LightScreen(card: card, section: section)
                case .climate: ACScreen(card: card)
                case .cover: CoverScreen(card: card, section: section)
                case .fan: FanScreen(card: card, section: section)
                case .media: MediaScreen(card: card)
                case .lock: LockScreen(card: card)
                case .alarm: AlarmScreen(card: card)
                case .select: SelectScreen(card: card)
                case .number: NumberScreen(card: card)
                case .sensor, .binarySensor: SensorScreen(card: card)
                case .toggle, .scene, .script, .button: SwitchScreen(card: card, section: section)
                }
            }
        case .lightEffect(let id):
            if let (_, card) = app.locate(id) { LightEffectScreen(card: card) }
        case .climateOption(let id, let option):
            if let (_, card) = app.locate(id) { ACOptionScreen(card: card, option: option) }
        }
    }
}

/// Small error capsule at the bottom of the panel when a service call fails.
private struct ErrorToast: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let message = app.lastError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.regularMaterial))
                .padding(.bottom, 10)
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Reports whether the hosting window (the MenuBarExtra panel) is on screen.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
            guard let window else {
                report(false)
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                        [weak self] note in
                        let closing = note.name == NSWindow.willCloseNotification
                        MainActor.assumeIsolated { self?.update(closing: closing) }
                    })
            }
            update(closing: false)
        }

        private func update(closing: Bool) {
            guard let window, !closing else {
                report(false)
                return
            }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            let callback = onChange
            // Defer out of the view update cycle.
            DispatchQueue.main.async { callback?(visible) }
        }
    }
}
