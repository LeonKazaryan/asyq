import simd

/// A stand-in rival until the real bot (M5): picks a kenei near the middle, aims straight at
/// it with a human spread in angle and power. No look-ahead, no tactics.
struct RivalBot: Sendable {
    let name: String
    private var random: SeededRandom

    init(name: String, seed: UInt64) {
        self.name = name
        random = SeededRandom(seed: seed)
    }

    /// A throw at one of `kenei` (positions), from `spot` with the throw's axis toward
    /// `target`. Half a pull lands on the target (`ThrowInput.range`); a hair more strikes the
    /// kenei rather than falling short of them.
    mutating func chooseThrow(spot: SIMD3<Float>, target: SIMD3<Float>, kenei: [SIMD3<Float>]) -> ThrowInput {
        let tuning = GameTuning.Rival.self
        var forward = target - spot
        forward.y = 0
        let axisLength = SimMath.length(forward)
        guard axisLength > 0 else { return ThrowInput(angle: 0, power: tuning.power) }
        forward /= axisLength
        let right = SimMath.cross(forward, [0, 1, 0])

        // The kenei closest to the line of the throw, picking among the nearest few.
        let candidates = kenei
            .map { (lateral: SimMath.dot($0 - spot, right), along: SimMath.dot($0 - spot, forward)) }
            .filter { $0.along > 0.3 }
            .sorted { abs($0.lateral) < abs($1.lateral) }
            .prefix(3)
        let choice = candidates.isEmpty ? nil : Array(candidates)[Int(random.fraction() * Float(candidates.count)) % candidates.count]
        let lateral = choice?.lateral ?? 0
        let along = choice?.along ?? axisLength
        // Small angles: atan(x) ≈ x − x³/3 is plenty within ±8°.
        let ratio = lateral / along
        let angle = ratio - ratio * ratio * ratio / 3
        let share = along / axisLength * (1 + tuning.overshoot)
        let power = (share - GameTuning.Throw.minRangeShare) / (GameTuning.Throw.maxRangeShare - GameTuning.Throw.minRangeShare)
        return ThrowInput(
            angle: angle + random.spread() * tuning.aimSpread,
            power: power + random.spread() * tuning.powerSpread
        )
    }

    mutating func chooseSpin() -> (strength: Float, tilt: Float) {
        (0.4 + 0.6 * random.fraction(), random.unit())
    }
}
