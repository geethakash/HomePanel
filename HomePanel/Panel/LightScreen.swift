import HAKit
import SwiftUI

/// Device screen for a light. Brightness, color, color temperature and effects show only when
/// the light supports them; preset and speed come from the card's attachments (e.g. WLED's
/// preset select and speed number).
struct LightScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let section: CardSection

    // Slider state: while dragging (and briefly after release) show the local value,
    // so the slider doesn't jump back before HA confirms.
    @State private var brightness: Double = 0
    @State private var brightnessHeldUntil = Date.distantPast
    @State private var editingBrightness = false
    @State private var brightnessDebouncer = Debouncer()

    @State private var kelvin: Double = 0
    @State private var kelvinHeldUntil = Date.distantPast
    @State private var editingKelvin = false
    @State private var kelvinDebouncer = Debouncer()

    @State private var speed: Double = 0
    @State private var speedHeldUntil = Date.distantPast
    @State private var editingSpeed = false
    @State private var speedDebouncer = Debouncer()

    static let swatches: [(name: String, rgb: [Int])] = [
        ("Red", [255, 0, 0]),
        ("Warm white", [255, 160, 60]),
        ("Yellow", [255, 200, 0]),
        ("Green", [0, 255, 0]),
        ("Cyan", [0, 255, 255]),
        ("Blue", [0, 0, 255]),
        ("Purple", [128, 0, 255]),
        ("Pink", [255, 0, 128]),
        ("White", [255, 255, 255]),
    ]

    var body: some View {
        let light = app.store[card.entityID]
        let isOn = light?.isOn ?? false

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(app.displayName(card)) {
                PowerButton(isOn: isOn, label: app.displayName(card)) { app.toggle(card.entityID) }
                    .rollbackShake(card.entityID)
                    .disabled(light?.isAvailable != true)
            }

            preview(light)

            if light?.supportsBrightness ?? true {
                PanelSection("Brightness") {
                    GlassSlider(
                        value: brightnessBinding(light),
                        systemImage: "sun.max.fill",
                        valueLabel: "\(Int((shownBrightness(light) * 100).rounded()))%",
                        accessibilityName: "Brightness",
                        onEditingChanged: { editing in
                            editingBrightness = editing
                            if !editing {
                                brightnessDebouncer.flush()
                                brightnessHeldUntil = .now.addingTimeInterval(1.5)
                            }
                        })
                }
            }

            if let light, light.supportsColorTemp {
                PanelSection("White") {
                    GlassSlider(
                        value: kelvinBinding(light),
                        systemImage: "thermometer.sun.fill",
                        valueLabel: "\(Int(kelvinValue(light, fraction: shownKelvin(light)).rounded())) K",
                        tint: Kelvin.color(kelvinValue(light, fraction: shownKelvin(light))),
                        accessibilityName: "Color temperature",
                        onEditingChanged: { editing in
                            editingKelvin = editing
                            if !editing {
                                kelvinDebouncer.flush()
                                kelvinHeldUntil = .now.addingTimeInterval(1.5)
                            }
                        })
                }
            }

            if light?.supportsColor ?? false {
                PanelSection("Color") {
                    swatches(light)
                }
            }

            if let presetID = card.attachment(.preset)?.entityID, let preset = app.store[presetID],
                !preset.options.isEmpty
            {
                PanelSection("Presets") {
                    PillFlow(
                        options: preset.options.map { PillOption(value: $0, label: $0) },
                        selected: preset.state
                    ) { app.selectOption(presetID, $0) }
                }
            }

            let hasEffects = !(light?.effectList.isEmpty ?? true)
            let speedNumber = card.attachment(.speed).flatMap { app.store[$0.entityID] }
            if hasEffects || speedNumber != nil {
                PanelSection(hasEffects ? "Effect" : "Speed") {
                    if hasEffects { effectRow(light) }
                    if let number = speedNumber {
                        GlassSlider(
                            value: speedBinding(number),
                            systemImage: "speedometer",
                            valueLabel: "\(Int(shownSpeed(number) * maxSpeed(number)))",
                            accessibilityName: "Effect speed",
                            onEditingChanged: { editing in
                                editingSpeed = editing
                                if !editing {
                                    speedDebouncer.flush()
                                    speedHeldUntil = .now.addingTimeInterval(1.5)
                                }
                            })
                    }
                }
            }

            let all = section.cards.filter { $0.kind == .light }.map(\.entityID)
            if all.count > 1 {
                PanelSection("All in \(section.title)") {
                    HStack(spacing: 8) {
                        CapsuleButton(title: "All on", systemImage: SFSymbol.filled(card.displayIcon)) {
                            app.setOn(all, true)
                        }
                        CapsuleButton(title: "All off", systemImage: card.displayIcon) { app.setOn(all, false) }
                    }
                }
            }
        }
    }

    // MARK: Preview strip

    private func preview(_ light: HAState?) -> some View {
        let isOn = light?.isOn ?? false
        let rgb = Self.displayRGB(light)
        let effect = light?.effect ?? ""
        let rainbow = ["rainbow", "colorloop", "color loop"].contains { effect.lowercased().contains($0) }
        let level = isOn ? max(0.15, shownBrightness(light)) : 0
        let fill: AnyShapeStyle =
            rainbow
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink],
                    startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(Color(rgb: rgb))
        let status: String = {
            guard let light else { return "Unavailable" }
            if !light.isAvailable { return "\(app.displayName(card)) · unavailable" }
            if !isOn { return "\(app.displayName(card)) · Off" }
            let preset = card.attachment(.preset).flatMap { app.store[$0.entityID]?.state }
            let detail = [preset, light.effect].compactMap { $0 }.first { $0 != "unknown" && !$0.isEmpty }
            return [app.displayName(card), detail].compactMap { $0 }.joined(separator: " · ")
        }()

        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(fill)
                    .opacity(level)
                    .shadow(color: (rainbow ? Color.purple : Color(rgb: rgb)).opacity(level * 0.8), radius: 12)
            }
            .frame(height: 18)
            .animation(.easeInOut(duration: 0.4), value: level)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// The light's color for the preview: its RGB, or its white temperature, or warm white.
    static func displayRGB(_ light: HAState?) -> [Int] {
        if let light, light.colorMode == "color_temp", let k = light.colorTempKelvin { return Kelvin.rgb(k) }
        return light?.rgb ?? (light?.colorTempKelvin.map(Kelvin.rgb) ?? [255, 214, 170])
    }

    // MARK: Color swatches

    private func swatches(_ light: HAState?) -> some View {
        let current = light?.isOn == true ? light?.rgb : nil
        let selectedIndex: Int? = current.flatMap { c in
            let best = Self.swatches.indices.min { RGB.distance(Self.swatches[$0].rgb, c) < RGB.distance(Self.swatches[$1].rgb, c) }
            return best.flatMap { RGB.distance(Self.swatches[$0].rgb, c) < 60 ? $0 : nil }
        }
        return HStack(spacing: 0) {
            ForEach(Self.swatches.indices, id: \.self) { i in
                let swatch = Self.swatches[i]
                Button {
                    app.lightOn(card.entityID, ["rgb_color": .array(swatch.rgb.map { .integer($0) })])
                } label: {
                    Circle()
                        .fill(Color(rgb: swatch.rgb))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .padding(3)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: 2)
                                .opacity(selectedIndex == i ? 1 : 0)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(selectedIndex == i ? .isSelected : [])
            }
        }
    }

    // MARK: Effect

    private func effectRow(_ light: HAState?) -> some View {
        Button {
            app.push(.lightEffect(card.id))
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Effect")
                Spacer()
                Text(light?.effect ?? "–")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(TileBackground(radius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(light?.effectList.isEmpty ?? true)
        .accessibilityLabel("Effect, \(light?.effect ?? "none")")
    }

    // MARK: Slider bindings

    private func shownBrightness(_ light: HAState?) -> Double {
        if editingBrightness || Date.now < brightnessHeldUntil { return brightness }
        guard let light, light.isOn else { return 0 }
        return Double(light.brightnessPct ?? 100) / 100
    }

    private func brightnessBinding(_ light: HAState?) -> Binding<Double> {
        Binding(
            get: { shownBrightness(light) },
            set: { newValue in
                brightness = newValue
                let pct = Int((newValue * 100).rounded())
                brightnessDebouncer.call { [app, card] in
                    if pct == 0 {
                        app.setOn([card.entityID], false)
                    } else {
                        app.lightOn(card.entityID, ["brightness_pct": .integer(pct)])
                    }
                }
            })
    }

    private func kelvinValue(_ light: HAState, fraction: Double) -> Double {
        light.minColorTempKelvin + fraction * (light.maxColorTempKelvin - light.minColorTempKelvin)
    }

    private func shownKelvin(_ light: HAState) -> Double {
        if editingKelvin || Date.now < kelvinHeldUntil { return kelvin }
        let span = light.maxColorTempKelvin - light.minColorTempKelvin
        guard let k = light.colorTempKelvin, span > 0 else { return 0.5 }
        return min(1, max(0, (k - light.minColorTempKelvin) / span))
    }

    private func kelvinBinding(_ light: HAState) -> Binding<Double> {
        Binding(
            get: { shownKelvin(light) },
            set: { newValue in
                kelvin = newValue
                let k = Int(kelvinValue(light, fraction: newValue).rounded())
                kelvinDebouncer.call { [app, card] in
                    app.lightOn(card.entityID, ["color_temp_kelvin": .integer(k)])
                }
            })
    }

    private func maxSpeed(_ number: HAState) -> Double { number.maxValue ?? 255 }

    private func shownSpeed(_ number: HAState) -> Double {
        if editingSpeed || Date.now < speedHeldUntil { return speed }
        return (number.numericState ?? 0) / maxSpeed(number)
    }

    private func speedBinding(_ number: HAState) -> Binding<Double> {
        Binding(
            get: { shownSpeed(number) },
            set: { newValue in
                speed = newValue
                let value = (newValue * maxSpeed(number)).rounded()
                speedDebouncer.call { [app, speedID = number.entityID] in app.setNumber(speedID, value) }
            })
    }
}

/// Effect list for one light, pushed inside the panel (no menus or popovers).
struct LightEffectScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card
    @State private var filter = ""

    var body: some View {
        let light = app.store[card.entityID]
        let effects = (light?.effectList ?? []).filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }

        VStack(alignment: .leading, spacing: 12) {
            BackHeader(app.displayName(card))
            Text("Effect")
                .font(.system(size: 15, weight: .semibold))
            TextField("Search effects", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TileBackground(radius: 10))
            LazyVStack(spacing: 2) {
                ForEach(effects, id: \.self) { effect in
                    OptionRow(title: effect, isSelected: effect == light?.effect) {
                        app.lightOn(card.entityID, ["effect": .string(effect)])
                    }
                }
            }
            .padding(4)
            .background(TileBackground(radius: 14))
            if effects.isEmpty {
                Text("No effects match.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Approximate colors for white color temperatures.
enum Kelvin {
    /// Tanner Helland's approximation, 1000–40000 K.
    static func rgb(_ kelvin: Double) -> [Int] {
        let t = min(40000, max(1000, kelvin)) / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        return [r, g, b].map { Int(min(255, max(0, $0))) }
    }

    static func color(_ kelvin: Double) -> Color { Color(rgb: rgb(kelvin)) }
}
