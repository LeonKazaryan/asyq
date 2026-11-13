import CoreHaptics
import Foundation

/// The game's hands: a continuous hum while the slingshot is drawn, a snap on release, and a
/// tick for every real impact, scaled by how hard it hit (docs/02-design.md, «Хаптика»).
/// Core Haptics rather than `.sensoryFeedback`, which can't do a continuous, shaped buzz.
@MainActor
final class HapticsDirector {
    enum Impact {
        case boneOnBone
        case boneOnCarpet
        /// The saqa's first hit on the kon: the double knock.
        case saqaOnKon
    }

    var isEnabled = true

    private var engine: CHHapticEngine?
    private var tension: CHHapticAdvancedPatternPlayer?
    private var lastTick: TimeInterval = 0
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    init() {
        startEngine()
    }

    private func startEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            // After an interruption (a call, the app in the background) the engine resets; the
            // players it made are gone, so start over.
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.tension = nil
                    try? self?.engine?.start()
                }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    // MARK: - Slingshot

    /// The finger takes the saqa: a soft tick, then the hum begins at nothing.
    func beginPull() {
        transient(intensity: 0.45, sharpness: 0.35)
        guard isEnabled, let engine else { return }
        do {
            let hum = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                ],
                relativeTime: 0,
                duration: 30
            )
            let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [hum], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            tension = player
            updatePull(power: 0)
        } catch {
            tension = nil
        }
    }

    /// The hum grows with the pull, and gets grittier toward full power.
    func updatePull(power: Double) {
        guard let tension else { return }
        let intensity = Float(0.08 + 0.5 * power * power)
        let sharpness = Float(0.15 + 0.5 * power)
        try? tension.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    /// Let go: the hum stops dead and the saqa snaps away.
    func release(power: Double) {
        stopTension()
        transient(intensity: Float(0.6 + 0.4 * power), sharpness: 0.95)
    }

    func cancelPull() {
        stopTension()
        transient(intensity: 0.3, sharpness: 0.2)
    }

    private func stopTension() {
        try? tension?.stop(atTime: CHHapticTimeImmediate)
        tension = nil
    }

    // MARK: - Impacts

    /// One collision. Ticks closer together than `minTickInterval` merge, so a burst of hits
    /// in slow motion stays a rattle, not a drone.
    func impact(_ kind: Impact, speed: Float) {
        let tuning = GameTuning.Feel.self
        guard speed >= tuning.minImpactSpeed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTick >= tuning.minTickInterval else { return }
        lastTick = now
        let strength = min(sqrt(speed / tuning.fullImpactSpeed), 1)
        switch kind {
        case .boneOnBone:
            transient(intensity: 0.35 + 0.65 * strength, sharpness: 0.85)
        case .boneOnCarpet:
            transient(intensity: 0.2 + 0.5 * strength, sharpness: 0.25)
        case .saqaOnKon:
            transient(intensity: 0.5 + 0.5 * strength, sharpness: 0.9, echo: 0.045)
        }
    }

    /// Kenei flew out: a short rising run, one beat per kenei up to three.
    func knockedOut(count: Int) {
        let beats = min(max(count, 1), 3)
        let events = (0..<beats).map { beat in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55 + 0.15 * Float(beat)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5 + 0.2 * Float(beat)),
                ],
                relativeTime: 0.07 * Double(beat)
            )
        }
        play(events)
    }

    func miss() {
        transient(intensity: 0.25, sharpness: 0.1)
    }

    // MARK: - Playing

    private func transient(intensity: Float, sharpness: Float, echo: TimeInterval? = nil) {
        var events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            ),
        ]
        if let echo {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness * 0.8),
                ],
                relativeTime: echo
            ))
        }
        play(events)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard isEnabled, let engine else { return }
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // The engine stopped (auto shutdown): wake it for the next event.
            try? engine.start()
        }
    }
}
