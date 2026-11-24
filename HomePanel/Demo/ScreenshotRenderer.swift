#if DEBUG
import AppKit
import HAKit
import SwiftUI

/// Renders README screenshots of the demo home. Run by Tools/make-screenshots.sh, which
/// launches a debug build with `--render-screenshots <folder>`.
@MainActor
enum ScreenshotRenderer {
    static func run(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folderURL = folder
        let app = DemoHome.makeModel()
        let room = app.currentRoom!
        func card(_ entityID: String) -> (CardSection, Card) {
            for section in room.sections {
                if let card = section.cards.first(where: { $0.entityID == entityID }) { return (section, card) }
            }
            fatalError("Demo card \(entityID) missing")
        }

        render("home-dark", dark: true, app) { HomeScreen() }
        render("home-light", dark: false, app) { HomeScreen() }
        let (_, ac) = card("climate.living_ac")
        render("climate", dark: true, app) { ACScreen(card: ac) }
        let (lights, strip) = card("light.tv_strip")
        render("light", dark: true, app) { LightScreen(card: strip, section: lights) }
        app.showingRooms = true
        render("rooms", dark: true, app) { HomeScreen() }
        app.showingRooms = false
    }

    private static func render<Content: View>(
        _ name: String, dark: Bool, _ app: AppModel, @ViewBuilder _ content: () -> Content
    ) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let view = ScreenshotFrame(dark: dark) { content() }
            .environment(app)
            .environment(\.colorScheme, dark ? .dark : .light)
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else {
                print("Couldn't render \(name)")
                return
            }
            let url = folderURL.appending(path: "\(name).png")
            do {
                try png.write(to: url)
                print("Rendered \(url.lastPathComponent) \(image.width)×\(image.height)")
            } catch {
                print("Couldn't write \(name): \(error.localizedDescription)")
            }
        }
    }

    private static var folderURL = URL.temporaryDirectory
}

/// A panel-shaped frosted card on a soft gradient, standing in for the menu bar panel's glass.
private struct ScreenshotFrame<Content: View>: View {
    let dark: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.padding)
            .frame(width: Theme.panelWidth)
            .background {
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(dark ? Color(white: 0.12).opacity(0.84) : Color(white: 0.97).opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(dark ? 0.16 : 0.7), lineWidth: 0.5))
                    .shadow(color: .black.opacity(dark ? 0.45 : 0.18), radius: 26, y: 14)
            }
            .padding(36)
            .background(
                LinearGradient(
                    colors: dark
                        ? [Color(hex: 0x23305E), Color(hex: 0x4A2F6E), Color(hex: 0x123B52)]
                        : [Color(hex: 0xB7CCF7), Color(hex: 0xD9E8F6), Color(hex: 0xF2D4E8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
#endif
