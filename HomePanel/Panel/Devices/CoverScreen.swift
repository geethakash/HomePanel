import HAKit
import SwiftUI

/// Blinds, curtains, garage doors…: open / stop / close, position and tilt when supported.
struct CoverScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let section: CardSection

    var body: some View {
        let cover = app.store[card.entityID]
        let f = cover?.coverFeatures ?? []
        let name = app.displayName(card)

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(name) {
                Text(section.title).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                CoverVisual(position: visualPosition(cover), systemImage: DeviceIcon.symbol(card, cover))
                Text(cover.map(DeviceText.summary) ?? "Unavailable")
                    .font(.system(size: 15, weight: .semibold))
                if let cover, let since = SinceText.text("Changed", cover.lastChanged) {
                    Text(since).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                if f.contains(.open) {
                    CapsuleButton(title: "Open", systemImage: "chevron.up") { send("open_cover") }
                }
                if f.contains(.stop) {
                    CapsuleButton(title: "Stop", systemImage: "stop.fill") { send("stop_cover") }
                }
                if f.contains(.close) {
                    CapsuleButton(title: "Close", systemImage: "chevron.down") { send("close_cover") }
                }
            }
            .disabled(cover?.isAvailable != true)

            if f.contains(.setPosition), let cover {
                PanelSection("Position") {
                    LiveSlider(
                        value: Double(cover.coverPosition ?? (cover.state == "open" ? 100 : 0)) / 100,
                        systemImage: "arrow.up.and.down",
                        accessibilityName: "Position",
                        label: { "\(Int(($0 * 100).rounded()))%" }
                    ) { [app, id = card.entityID] v in
                        app.call("cover", "set_cover_position", [id], ["position": .integer(Int((v * 100).rounded()))])
                    }
                }
            }

            if f.contains(.setTiltPosition), let cover {
                PanelSection("Tilt") {
                    LiveSlider(
                        value: Double(cover.coverTilt ?? 0) / 100,
                        systemImage: "angle",
                        accessibilityName: "Tilt",
                        label: { "\(Int(($0 * 100).rounded()))%" }
                    ) { [app, id = card.entityID] v in
                        app.call(
                            "cover", "set_cover_tilt_position", [id], ["tilt_position": .integer(Int((v * 100).rounded()))])
                    }
                }
            } else if !f.isDisjoint(with: [.openTilt, .closeTilt]) {
                PanelSection("Tilt") {
                    HStack(spacing: 8) {
                        if f.contains(.openTilt) {
                            CapsuleButton(title: "Open tilt") { send("open_cover_tilt") }
                        }
                        if f.contains(.closeTilt) {
                            CapsuleButton(title: "Close tilt") { send("close_cover_tilt") }
                        }
                    }
                }
            }

            let all = section.cards.filter { $0.kind == .cover }.map(\.entityID)
            if all.count > 1 {
                PanelSection("All in \(section.title)") {
                    HStack(spacing: 8) {
                        CapsuleButton(title: "Open all", systemImage: "chevron.up") {
                            app.call("cover", "open_cover", all)
                        }
                        CapsuleButton(title: "Close all", systemImage: "chevron.down") {
                            app.call("cover", "close_cover", all)
                        }
                    }
                }
            }
        }
    }

    private func send(_ service: String) {
        app.call("cover", service, [card.entityID])
    }

    /// 0 = closed, 1 = open; covers without a position are fully open or closed.
    private func visualPosition(_ cover: HAState?) -> Double {
        guard let cover else { return 0 }
        if let p = cover.coverPosition { return Double(p) / 100 }
        return ["open", "opening"].contains(cover.state) ? 1 : 0
    }
}

/// A window with a blind that lowers as the cover closes.
private struct CoverVisual: View {
    let position: Double
    let systemImage: String

    var body: some View {
        let size = CGSize(width: 112, height: 150)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x64D2FF, opacity: 0.35), Color(hex: 0x0A84FF, opacity: 0.15)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 5) {
                ForEach(0..<14, id: \.self) { _ in
                    Capsule().fill(Color.primary.opacity(0.22)).frame(height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .frame(height: max(0, size.height * (1 - position)), alignment: .top)
            .clipped()
            .background(Color.primary.opacity(0.06))
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.5), value: position)
        .accessibilityHidden(true)
    }
}
