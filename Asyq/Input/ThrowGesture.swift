import CoreGraphics

/// The slingshot: pull down for power, sideways to aim the other way, flick on release for
/// spin. Pure math over finger positions, so it's testable without a screen.
struct ThrowGesture: Sendable {
    let start: CGPoint
    var current: CGPoint

    init(start: CGPoint) {
        self.start = start
        self.current = start
    }

    /// Finger travel since touch-down, in points; y grows downward.
    var pull: CGVector {
        CGVector(dx: current.x - start.x, dy: current.y - start.y)
    }

    var power: Double {
        min(max(Double(pull.dy) / GameTuning.Gesture.fullPull, 0), 1)
    }

    /// −1…1. Like a slingshot, pulling left sends it right.
    var aim: Double {
        min(max(-Double(pull.dx) / GameTuning.Gesture.fullAimPull, -1), 1)
    }

    var isLongEnough: Bool {
        Double(hypot(pull.dx, pull.dy)) >= GameTuning.Gesture.minPull && pull.dy > 0
    }

    /// The throw this gesture makes right now.
    var input: ThrowInput {
        ThrowInput(angle: Float(aim) * GameTuning.Throw.maxAimAngle, power: Float(power))
    }

    /// The throw on release, or nil when the pull was too short and should be cancelled.
    /// - Parameter releaseVelocity: the finger's speed at lift-off, points per second.
    func release(velocity releaseVelocity: CGVector) -> ThrowInput? {
        guard isLongEnough else { return nil }
        let sideways = Double(releaseVelocity.dx)
        let dead = GameTuning.Gesture.spinDeadZone
        let beyondDeadZone = abs(sideways) < dead ? 0 : sideways - (sideways > 0 ? dead : -dead)
        let spin = beyondDeadZone / GameTuning.Gesture.fullSpinVelocity
        return ThrowInput(angle: input.angle, power: input.power, spin: Float(spin))
    }
}
