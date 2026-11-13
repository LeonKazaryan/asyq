import simd

/// Every number that shapes how the game feels or how the physics behaves. Tune here and
/// nowhere else (CLAUDE.md). Lengths in meters, masses in kilograms, times in seconds.
enum GameTuning {
    /// Placeholder bones: rounded "pebbles" until the scans land (ADR-003). Local axes:
    /// X — length (ompy/shonqai ends), Y — thickness (buk/shik, the wide faces),
    /// Z — width (alshy/taike, the narrow sides).
    enum Bone {
        static let keneiHalfExtents = SIMD3<Float>(0.0145, 0.0085, 0.0105)
        static let keneiCornerRadius: Float = 0.0045
        /// Регламент, с. 66: not less than 15 g; the Kazakh part says 17 g.
        static let keneiMass: Float = 0.016
        static let saqaHalfExtents = SIMD3<Float>(0.0170, 0.0100, 0.0125)
        static let saqaCornerRadius: Float = 0.0055
        /// Регламент, каз. часть, с. 13: a saqa is at most 28–30 g.
        static let saqaMass: Float = 0.029
        static let linearDamping: Float = 0.05
        static let angularDamping: Float = 0.08
    }

    /// Friction and restitution per material pair (docs/research/game-design.md, «Материалы»).
    enum Surface {
        static let bone: UInt8 = 0
        static let carpet: UInt8 = 1
        static let boneOnBone = (friction: Float(0.30), restitution: Float(0.55))
        static let boneOnCarpet = (friction: Float(0.70), restitution: Float(0.15))
    }

    enum Simulation {
        static let stepRate: Float = 240
        /// Nothing is allowed to roll for longer than this after a throw: the turn must end.
        static let maxSettleTime: Float = 4
        /// Physics steps per rendered frame at most, so a hitch never snowballs.
        static let maxStepsPerFrame = 12
    }

    enum Field {
        /// Kenei closer than this to their slot, and barely turned, haven't moved.
        static let slotTolerance: Float = 0.002
        /// Gap between kenei on the kon is one saqa (Регламент, с. 62).
        static var keneiSpacing: Float { 2 * Bone.keneiHalfExtents.x + 2 * Bone.saqaHalfExtents.x }
        /// Kenei are placed this far above the carpet so they never start interpenetrating it.
        static let restingClearance: Float = 0.0004
    }

    enum Throw {
        /// Регламент-style aim limit, docs/research/game-design.md: ±8°.
        static let maxAimAngle: Float = 8 * .pi / 180
        /// Power maps linearly onto where the saqa would land on bare carpet, as a share of
        /// the distance to the target: the same pull means the same thing from every spot.
        static let minRangeShare: Float = 0.35
        static let maxRangeShare: Float = 1.65
        /// A low, flat throw from a crouch, as in real atu (ADR-010): the saqa comes down onto
        /// the target at this angle from every distance. Measured 2026-11-13, 33 throws per
        /// category and spot landing 20 cm short to 30 cm long: at 10° a hit knocks a kenei out
        /// 55–85% of the time everywhere, at 8° almost always, at 12° from 25% to 100%.
        static let arrivalAngle: Float = 10 * .pi / 180
        /// The hand's height for long throws; closer in it drops (`ThrowLaunch.releasePoint`).
        static let releaseHeight: Float = 0.35
        /// Behind the throw line: a throw must leave the hand before the line (Регламент, п. 1.4).
        static let releaseBehind: Float = 0.25
        /// Backspin around the thrower's right axis, rad/s: the saqa tumbles in flight.
        static let tumbleRate: Float = 14
        /// Side spin around the vertical at full flick, rad/s.
        static let maxSideSpin: Float = 30
        /// Dots along the trajectory preview.
        static let previewSamples = 28
    }

    enum Gesture {
        /// Finger travel, in points, for full power and full aim.
        static let fullPull: Double = 260
        static let fullAimPull: Double = 160
        /// Shorter pulls are cancelled, not thrown.
        static let minPull: Double = 22
        /// Sideways finger speed at release, points/s, for full side spin; slower is ignored.
        static let fullSpinVelocity: Double = 1800
        static let spinDeadZone: Double = 250
    }

    /// The saqa in the hand, placed relative to the aiming camera.
    enum Hand {
        /// In front of the aiming camera.
        static let distance: Float = 1.15
        /// The hand on screen: how far below the center, as a fraction of the half height.
        static let screenDrop: Float = 0.68
        /// At full pull the hand comes this much closer and this much lower on screen.
        static let pullBack: Float = 0.15
        static let pullScreenDrop: Float = 0.14
        /// On release the hand swings forward and down out of view; the real saqa comes up
        /// from below the frame.
        static let flick = SpringParameters(response: 0.16, dampingRatio: 1)
        static let idleSwayRate: Float = 0.6
        static let idleSwayAngle: Float = 0.22
        /// Without a touch the hand stops swaying and the screen stops drawing.
        static let idleTimeout: Double = 5
    }

    enum Camera {
        static let nearPlane: Float = 0.04
        static let farPlane: Float = 80
        /// Aiming: behind and above the throw spot, a long lens so the kon fills the width.
        static let aimBack: Float = 1.5
        static let aimHeight: Float = 1.25
        /// Fraction of the screen width the kon row should span when aiming from the line.
        static let aimRowFill: Float = 0.92
        /// Chasing the saqa: behind and above it, never closer to the kon than `chaseMinDistance`.
        static let chaseBack: Float = 0.85
        static let chaseHeight: Float = 0.38
        static let chaseMinDistance: Float = 1.5
        static let chaseFieldOfView: Float = 34 * .pi / 180
        /// Aiming at one kenei (a referee's command): the lens frames this much width.
        static let singleKeneiFraming: Float = 0.45
        /// After the first hit the camera swings round the impact by this much.
        static let impactOrbit: Float = 15 * .pi / 180
        static let impactDistance: Float = 1.15
        /// Simulated seconds the camera stays on the impact before rising to the overview.
        static let impactHold: Float = 0.45
        static let impactHeight: Float = 0.42
        /// Framing the result: kon, moving kenei and saqa, seen from `framePitch` above.
        static let framePitch: Float = 52 * .pi / 180
        static let frameDistance: Float = 2.6
        static let frameMargin: Float = 0.25
        static let frameMinReach: Float = 0.75
        static let frameMinFieldOfView: Float = 28 * .pi / 180
        static let frameMaxFieldOfView: Float = 64 * .pi / 180
        /// The view after everything stops: high behind the circle.
        static let overviewHeight: Float = 6.4
        static let overviewBack: Float = 4.6
        static let overviewFieldOfView: Float = 52 * .pi / 180

        static let aimSpring = SpringParameters(response: 0.75, dampingRatio: 0.92)
        static let chaseSpring = SpringParameters(response: 0.22, dampingRatio: 1)
        static let impactSpring = SpringParameters(response: 0.5, dampingRatio: 0.85)
        static let overviewSpring = SpringParameters(response: 0.95, dampingRatio: 0.9)
    }

    /// Spinning a saqa to decide who starts.
    enum Iiru {
        static let dropHeight: Float = 0.3
        static let dropSpeed: Float = 0.6
        /// rad/s about the length, from a lazy flick to a hard one.
        static let minSpin: Float = 18
        static let maxSpin: Float = 55
        static let twist: Float = 6
        /// Where it happens: just outside the circle on the home side, off the axis.
        static let besideCircle: Float = 0.8
        static let offAxis: Float = 0.6
        /// The two saqas land a hand apart.
        static let spacing: Float = 0.16
        /// A flick this fast, in points per second, spins at full strength.
        static let fullFlick: Double = 2600
    }

    /// The stand-in rival until M5.
    enum Rival {
        static let aimSpread: Float = 1.6 * .pi / 180
        /// Without a kenei to aim at: half a pull and a hair more.
        static let power: Float = 0.53
        /// Aims this share past the kenei, to strike rather than fall short.
        static let overshoot: Float = 0.04
        static let powerSpread: Float = 0.06
        /// Pause behind the line before the rival throws, seconds.
        static let thinkTime: Double = 1.1
    }

    enum SlowMotion {
        static let scale: Float = 0.2
        /// Simulated seconds the impact plays at `scale`: about 0.6 s on the clock.
        static let holdSimTime: Float = 0.12
        static let easeOut = SpringParameters(response: 0.45, dampingRatio: 1)
        /// Only a real hit slows time, not a graze.
        static let minImpactSpeed: Float = 1.2
    }

    enum Feel {
        /// Landings faster than this leave a ring on the felt.
        static let rippleSpeed: Float = 1.0
        /// Impacts slower than this make no haptic or ripple.
        static let minImpactSpeed: Float = 0.25
        /// Impact speed that gives the strongest tick.
        static let fullImpactSpeed: Float = 6
        /// Haptic ticks closer together than this merge into one (in real time).
        static let minTickInterval: Double = 0.028
    }

    enum Result {
        static let bannerTime: Double = 1.5
        static let restoreSpring = SpringParameters(response: 0.5, dampingRatio: 0.85)
        static let knockedOutPop = SpringParameters(response: 0.35, dampingRatio: 0.7)
    }

    enum Light {
        /// Toward the light: from the left, above, a little from behind the thrower.
        static let direction = simd_normalize(SIMD3<Float>(-0.42, 0.82, 0.38))
        /// Direct plus ambient ≈ 1 on the lit carpet, so palette colors read true.
        static let intensity: Float = 0.95
        static let ambient: Float = 0.32
        /// Shadow map covers this half-size around the action.
        static let shadowHalfExtent: Float = 4.8
        static let shadowMapSize = 2048
    }
}

extension GameTuning {
    /// Measures the Регламент leaves to us (docs/05-rules.md, 🟡).
    enum Rules {
        /// One taban, a foot: «Бес табан» is five of them along the circle, and a kenei within
        /// one of the circle line earns that command (каз. п. 2.1). docs/05-rules.md, question 8.
        static let taban: Float = 0.27
    }
}
