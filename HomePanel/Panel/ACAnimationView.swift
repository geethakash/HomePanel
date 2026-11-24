import HAKit
import SwiftUI

/// Animated wall unit: louver and blades on springs, airflow particles in the mode colour,
/// a pulsing glow, and feature flourishes (Health sparkles, Soft Wind waves, Eco green tint).
///
/// Runs only while the panel is open and this view is on screen. With Reduce Motion it draws
/// one still frame with arrows instead of particles.
struct ACAnimationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let state: ACVisualState

    @State private var simulation = ACSimulation()
    @State private var onScreen = false

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    let sim = ACSimulation.settled(for: state)
                    ACRenderer.draw(
                        in: &context, size: size, sim: sim, state: state, motion: false, dark: colorScheme == .dark)
                }
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: !(onScreen && app.panelVisible))) { timeline in
                    Canvas { context, size in
                        let layout = ACRenderer.Layout(size: size)
                        simulation.step(
                            to: timeline.date.timeIntervalSinceReferenceDate, state: state,
                            vent: layout.vent, floorY: size.height)
                        ACRenderer.draw(
                            in: &context, size: size, sim: simulation, state: state, motion: true,
                            dark: colorScheme == .dark)
                    }
                }
            }
        }
        .onAppear { onScreen = true }
        .onDisappear {
            onScreen = false
            simulation.pause()
        }
        .onChange(of: app.panelVisible) { _, visible in
            if !visible { simulation.pause() }
        }
    }
}

enum ACRenderer {
    struct Layout {
        let body: CGRect
        let vent: CGRect

        init(size: CGSize) {
            let width = min(232, size.width - 56)
            body = CGRect(x: (size.width - width) / 2, y: 16, width: width, height: 70)
            vent = CGRect(x: body.minX + 18, y: body.maxY - 17, width: width - 36, height: 9)
        }
    }

    /// `dark`: the panel's appearance. On a light background the airflow is drawn darker,
    /// since pale mode colours (Fan's grey, Cool's sky blue) would wash out.
    static func draw(
        in context: inout GraphicsContext, size: CGSize, sim: ACSimulation, state: ACVisualState, motion: Bool,
        dark: Bool = true
    ) {
        let layout = Layout(size: size)
        let modeColor = color(dark ? sim.color : sim.color * 0.62)
        let sparkleColor = dark ? Color.white : color(sim.color * 0.5)

        drawGlow(&context, layout: layout, sim: sim, size: size)
        drawBody(&context, layout: layout, sim: sim, state: state, motion: motion, modeColor: modeColor)
        drawVent(&context, layout: layout, sim: sim)
        if motion {
            drawParticles(&context, sim: sim, state: state, modeColor: modeColor, sparkleColor: sparkleColor)
        } else if state.isOn {
            drawArrows(&context, layout: layout, sim: sim, modeColor: modeColor)
        }
    }

    // MARK: Pieces

    private static func drawGlow(_ context: inout GraphicsContext, layout: Layout, sim: ACSimulation, size: CGSize) {
        guard sim.intensity > 0.01 else { return }
        let pulse = sin(sim.glowPhase)
        let scale = 1 + 0.06 * pulse
        let width = layout.body.width * 0.9 * scale
        let rect = CGRect(
            x: layout.body.midX - width / 2, y: layout.body.maxY + 30, width: width, height: 34 * scale)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 20))
            layer.fill(
                Path(ellipseIn: rect),
                with: .color(color(sim.glowColor).opacity(sim.intensity * (0.32 + 0.1 * pulse))))
        }
    }

    private static func drawBody(
        _ context: inout GraphicsContext, layout: Layout, sim: ACSimulation, state: ACVisualState, motion: Bool,
        modeColor: Color
    ) {
        let body = layout.body
        let shape = Path(roundedRect: body, cornerRadius: 15, style: .continuous)

        // Drop shadow + gradient body.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 4))
            layer.fill(
                shape,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xF5F7FB), Color(hex: 0xE3E7EE), Color(hex: 0xD2D7E0)]),
                    startPoint: CGPoint(x: body.midX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.maxY)))
        }

        var inner = context
        inner.clip(to: shape)
        // Inner shadow along the edges, and a soft top highlight.
        inner.stroke(shape, with: .color(.black.opacity(0.06)), lineWidth: 2.5)
        // Seam above the vent.
        inner.stroke(
            Path { p in
                p.move(to: CGPoint(x: body.minX, y: body.maxY - 24))
                p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - 24))
            }, with: .color(.black.opacity(0.06)), lineWidth: 1)

        // Glass highlight sweep, every 7 s.
        if motion {
            let progress = sim.time.truncatingRemainder(dividingBy: 7) / 7
            let x = body.minX - 60 + (body.width + 120) * progress * 1.6
            if x < body.maxX + 40 {
                let band = Path { p in
                    p.move(to: CGPoint(x: x, y: body.minY))
                    p.addLine(to: CGPoint(x: x + 22, y: body.minY))
                    p.addLine(to: CGPoint(x: x - 8, y: body.maxY))
                    p.addLine(to: CGPoint(x: x - 30, y: body.maxY))
                    p.closeSubpath()
                }
                inner.fill(
                    band,
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(0.4), .white.opacity(0)]),
                        startPoint: CGPoint(x: x - 30, y: body.midY), endPoint: CGPoint(x: x + 22, y: body.midY)))
            }
        }

        // Front display (hidden when Display is off) and status LED.
        let displayCenter = CGPoint(x: body.maxX - 40, y: body.minY + 22)
        if state.isOn, state.displayOn, let target = state.target {
            let text = context.resolve(
                Text("\(Int(target.rounded()))°")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(modeColor))
            context.drawLayer { layer in
                layer.opacity = sim.intensity
                layer.addFilter(.shadow(color: modeColor.opacity(0.9), radius: 3))
                layer.draw(text, at: displayCenter, anchor: .center)
            }
        }
        let led = CGRect(x: body.maxX - 19, y: body.minY + 19.5, width: 5, height: 5)
        context.drawLayer { layer in
            let on = state.isOn
            if on { layer.addFilter(.shadow(color: .green, radius: 2.5)) }
            layer.fill(Path(ellipseIn: led), with: .color(on ? .green : Color.gray.opacity(0.5)))
        }
    }

    private static func drawVent(_ context: inout GraphicsContext, layout: Layout, sim: ACSimulation) {
        let vent = layout.vent
        // How far the louver has opened from closed (−30°).
        let open = min(1, max(0, (sim.louver + 30) / 10))
        let ventShape = Path(roundedRect: vent, cornerRadius: 4.5, style: .continuous)
        context.fill(ventShape, with: .color(Color(hex: 0x2A2E36).opacity(0.25 + 0.75 * open)))

        // Horizontal-direction blades inside the vent.
        if open > 0.05 {
            var blades = context
            blades.clip(to: ventShape)
            let offset = tan(sim.blade * .pi / 180) * 4
            let count = 11
            for i in 0..<count {
                let x = vent.minX + vent.width * (Double(i) + 0.5) / Double(count)
                blades.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x - offset, y: vent.minY))
                        p.addLine(to: CGPoint(x: x + offset, y: vent.maxY))
                    }, with: .color(Color(hex: 0x8A909C).opacity(open)), lineWidth: 1.4)
            }
        }

        // Vertical louver plate, hinged at the bottom of the vent. Its visible depth grows as it
        // points further down; closed, it lies flat over the vent.
        let downness = min(1, max(0, (sim.louver + 30) / 54))
        let depth = 2 + 11 * downness
        let inset = 3 + 3 * downness
        let plate = Path { p in
            p.move(to: CGPoint(x: vent.minX - 2, y: vent.maxY - (1 - open) * vent.height))
            p.addLine(to: CGPoint(x: vent.maxX + 2, y: vent.maxY - (1 - open) * vent.height))
            p.addLine(to: CGPoint(x: vent.maxX + 2 - inset, y: vent.maxY + depth * open))
            p.addLine(to: CGPoint(x: vent.minX - 2 + inset, y: vent.maxY + depth * open))
            p.closeSubpath()
        }
        context.fill(
            plate,
            with: .linearGradient(
                Gradient(colors: [Color(hex: 0xE9ECF2), Color(hex: 0xC3C9D3)]),
                startPoint: CGPoint(x: vent.midX, y: vent.minY), endPoint: CGPoint(x: vent.midX, y: vent.maxY + depth)))
        context.stroke(plate, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
    }

    private static func drawParticles(
        _ context: inout GraphicsContext, sim: ACSimulation, state: ACVisualState, modeColor: Color,
        sparkleColor: Color
    ) {
        guard !sim.particles.isEmpty else { return }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.8))
            for p in sim.particles where !p.sparkle {
                let t = p.age / p.life
                let alpha = pow(1 - t, 1.5) * min(1, p.age * 10) * 0.7 * sim.intensity
                guard alpha > 0.01 else { continue }
                var x = p.x
                if state.softWind {
                    x += sin(p.age * 4 + p.seed * 2 * .pi) * 7 * min(1, p.age * 2)
                }
                // A short streak along the velocity reads as moving air.
                let tail = 0.07
                layer.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x - p.vx * tail, y: p.y - p.vy * tail))
                        path.addLine(to: CGPoint(x: x, y: p.y))
                    },
                    with: .color(modeColor.opacity(alpha)),
                    style: StrokeStyle(lineWidth: p.size * (1 + 0.6 * t), lineCap: .round))
            }
        }
        // Health sparkles: tiny twinkling points, not blurred.
        for p in sim.particles where p.sparkle {
            let t = p.age / p.life
            let twinkle = 0.5 + 0.5 * sin(p.age * 18 + p.seed * 10)
            let alpha = (1 - t) * twinkle * sim.intensity
            guard alpha > 0.02 else { continue }
            let r = 1.1 + twinkle
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                with: .color(sparkleColor.opacity(alpha)))
        }
    }

    /// Reduce Motion: three still arrows showing the air direction instead of particles.
    private static func drawArrows(_ context: inout GraphicsContext, layout: Layout, sim: ACSimulation, modeColor: Color) {
        var arrow = context.resolve(Image(systemName: "arrow.down"))
        arrow.shading = .color(modeColor)
        let downness = min(1, max(0, (sim.louver + 30) / 54))
        let tilt = -sim.blade * 0.9
        for i in -1...1 {
            var c = context
            c.translateBy(x: layout.vent.midX + Double(i) * 42, y: layout.vent.maxY + 22 + 6 * downness)
            c.rotate(by: .degrees(tilt + Double(i) * 6))
            c.draw(arrow, in: CGRect(x: -8, y: -9, width: 16, height: 18))
        }
    }

    private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z)
    }
}
