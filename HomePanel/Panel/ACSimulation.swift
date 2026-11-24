import Foundation
import HAKit

/// Frame-by-frame physics for the A/C animation: louver and blade springs, colour cross-fade,
/// power fade, glow pulse and airflow particles. Stepped from the Canvas on every display frame.
final class ACSimulation {
    struct Particle {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var age: Double = 0
        var life: Double
        var size: Double
        var sparkle: Bool
        var seed: Double
    }

    static let maxParticles = 300

    private(set) var particles: [Particle] = []
    /// Vertical louver angle in degrees (negative = up, −30 = closed).
    private(set) var louver = -30.0
    private var louverVelocity = 0.0
    /// Horizontal blade angle in degrees (negative = left).
    private(set) var blade = 0.0
    private var bladeVelocity = 0.0
    /// Mode colour (linear 0…1 RGB), cross-faded on mode changes.
    private(set) var color = ACSimulation.offColor
    private(set) var glowColor = ACSimulation.offColor
    /// 0 when off, 1 when running; fades particles and glow in and out.
    private(set) var intensity = 0.0
    private(set) var glowPhase = 0.0
    private(set) var time = 0.0

    private var lastTimestamp: Double?
    private var emitCarry = 0.0

    static let offColor = SIMD3<Double>(0.63, 0.65, 0.69)
    static let ecoGreen = SIMD3<Double>(0x30, 0xD1, 0x58) / 255

    init() {
        particles.reserveCapacity(Self.maxParticles)
    }

    // MARK: Targets

    static func rgb(for mode: String) -> SIMD3<Double> {
        guard let hex = HVACMode.hex(mode) else { return offColor }
        return SIMD3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
    }

    private static func swing(_ low: Double, _ high: Double, t: Double, period: Double) -> Double {
        (low + high) / 2 + (high - low) / 2 * sin(2 * .pi * t / period)
    }

    /// Louver target at time `t`. Swing options sweep, fixed options hold, off closes at −30°.
    static func louverTarget(_ s: ACVisualState, t: Double) -> Double {
        guard s.isOn else { return -30 }
        switch s.upDown {
        case .sweep(.full): return swing(-18, 18, t: t, period: 4.2)
        case .sweep(.first): return swing(-22, -6, t: t, period: 3.6)
        case .sweep(.middle): return swing(-8, 8, t: t, period: 3.6)
        case .sweep(.last): return swing(6, 22, t: t, period: 3.6)
        case .fixed(let x): return 24 * x
        }
    }

    static func bladeTarget(_ s: ACVisualState, t: Double) -> Double {
        guard s.isOn else { return 0 }
        switch s.leftRight {
        case .sweep(.full): return swing(-30, 30, t: t, period: 5.2)
        case .sweep(.first): return swing(-30, -10, t: t, period: 4)
        case .sweep(.middle): return swing(-10, 10, t: t, period: 4)
        case .sweep(.last): return swing(10, 30, t: t, period: 4)
        case .fixed(let x): return 30 * x
        }
    }

    /// Emission rate (particles/s), speed (pt/s) and angular spread (radians) per fan level.
    static func fan(_ level: FanLevel) -> (rate: Double, speed: Double, spread: Double) {
        switch level {
        case .quiet: (55, 34, 0.16)
        case .low: (85, 50, 0.2)
        case .medium: (125, 70, 0.24)
        case .high: (170, 95, 0.28)
        case .turbo: (240, 140, 0.34)
        case .auto: (115, 66, 0.24)
        }
    }

    /// Glow pulses slower as the room approaches the target.
    static func pulseHz(_ s: ACVisualState) -> Double {
        guard let room = s.roomTemperature, let target = s.target else { return 0.3 }
        let distance = min(1, abs(room - target) / 6)
        return 0.1 + 0.4 * distance
    }

    // MARK: Stepping

    /// A simulation already at rest for `state` (used for Reduce Motion and the first frame).
    static func settled(for state: ACVisualState) -> ACSimulation {
        let sim = ACSimulation()
        sim.snap(to: state)
        return sim
    }

    private func snap(to s: ACVisualState) {
        louver = Self.louverTarget(s, t: 0)
        blade = Self.bladeTarget(s, t: 0)
        color = s.isOn ? Self.rgb(for: s.mode) : Self.offColor
        glowColor = s.eco ? color + (Self.ecoGreen - color) * 0.35 : color
        intensity = s.isOn ? 1 : 0
    }

    func pause() {
        lastTimestamp = nil
    }

    /// Advances to `timestamp` (seconds). `vent` is the vent opening in canvas coordinates.
    func step(to timestamp: Double, state s: ACVisualState, vent: CGRect, floorY: Double) {
        guard let last = lastTimestamp else {
            // First frame: start at rest and pre-warm the airflow so it doesn't pop in.
            lastTimestamp = timestamp
            if time == 0 {
                snap(to: s)
                for _ in 0..<40 { advance(dt: 1.0 / 30, state: s, vent: vent, floorY: floorY) }
            }
            return
        }
        let dt = min(1.0 / 30, max(0, timestamp - last))
        lastTimestamp = timestamp
        advance(dt: dt, state: s, vent: vent, floorY: floorY)
    }

    private func advance(dt: Double, state s: ACVisualState, vent: CGRect, floorY: Double) {
        guard dt > 0 else { return }
        time += dt

        // Springs: slightly under-damped so fixed positions snap with a small bounce.
        spring(&louver, &louverVelocity, to: Self.louverTarget(s, t: time), stiffness: 90, damping: 11, dt: dt)
        spring(&blade, &bladeVelocity, to: Self.bladeTarget(s, t: time), stiffness: 70, damping: 10, dt: dt)

        // Colour cross-fade (~0.6 s) and power fade (~0.5 s).
        let targetColor = s.isOn ? Self.rgb(for: s.mode) : color
        let k = 1 - exp(-dt / 0.15)
        color += (targetColor - color) * k
        let targetGlow = s.eco ? color + (Self.ecoGreen - color) * 0.35 : color
        glowColor += (targetGlow - glowColor) * k
        intensity += ((s.isOn ? 1 : 0) - intensity) * (1 - exp(-dt / 0.12))

        glowPhase += 2 * .pi * Self.pulseHz(s) * dt

        updateParticles(dt: dt, state: s, vent: vent, floorY: floorY)
    }

    private func spring(
        _ x: inout Double, _ v: inout Double, to target: Double, stiffness: Double, damping: Double, dt: Double
    ) {
        let a = stiffness * (target - x) - damping * v
        v += a * dt
        x += v * dt
    }

    private func updateParticles(dt: Double, state s: ACVisualState, vent: CGRect, floorY: Double) {
        let fan = Self.fan(s.fan)
        let soft = s.softWind ? 0.8 : 1

        // Age and move.
        for i in particles.indices {
            particles[i].age += dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vx *= 1 - 0.6 * dt  // air drag
            particles[i].vy *= 1 - 0.4 * dt
        }
        particles.removeAll { $0.age >= $0.life || $0.y > floorY + 10 }

        // Emit.
        guard s.isOn, intensity > 0.05 else {
            emitCarry = 0
            return
        }
        emitCarry += fan.rate * intensity * dt
        let downness = min(1, max(0, (louver + 30) / 54))  // 0 = up/outward, 1 = down
        let bladeRad = blade * .pi / 180
        while emitCarry >= 1 {
            emitCarry -= 1
            guard particles.count < Self.maxParticles else { continue }
            let jitter = Double.random(in: -fan.spread...fan.spread)
            let speed = fan.speed * soft * Double.random(in: 0.75...1.2)
            let angle = bladeRad * 0.9 + jitter
            particles.append(
                Particle(
                    x: Double.random(in: vent.minX + 4...vent.maxX - 4),
                    y: vent.maxY + 2,
                    vx: speed * sin(angle),
                    vy: speed * (0.45 + 0.55 * downness) * cos(jitter),
                    life: Double.random(in: 0.9...1.5),
                    size: Double.random(in: 1.8...3.4),
                    sparkle: s.health && Double.random(in: 0...1) < 0.1,
                    seed: Double.random(in: 0...1)
                ))
        }
    }
}
