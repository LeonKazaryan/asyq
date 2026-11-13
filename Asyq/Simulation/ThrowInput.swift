import simd

/// One move: everything the player decides in a throw. With the table's starting state it
/// determines the outcome exactly (docs/03-architecture.md, «Детерминизм»), so a turn can be
/// replayed, simulated by the bot, or later sent over the network as three numbers.
struct ThrowInput: Hashable, Sendable, Codable {
    /// Radians from straight at the kon, positive to the thrower's right.
    var angle: Float
    /// 0…1: where the saqa would land on bare carpet, as a share of the distance to the
    /// target (`range(over:)`). Half a pull lands on the target from any spot.
    var power: Float
    /// −1…1, side spin from the flick of the release.
    var spin: Float

    init(angle: Float, power: Float, spin: Float = 0) {
        let limit = GameTuning.Throw.maxAimAngle
        self.angle = min(max(angle, -limit), limit)
        self.power = min(max(power, 0), 1)
        self.spin = min(max(spin, -1), 1)
    }

    /// Where the saqa would land on bare carpet, meters from a spot `distance` from the target.
    func range(over distance: Float) -> Float {
        let tuning = GameTuning.Throw.self
        return distance * (tuning.minRangeShare + power * (tuning.maxRangeShare - tuning.minRangeShare))
    }
}

/// How the saqa leaves the hand for a given input.
struct ThrowLaunch: Sendable {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var linearVelocity: SIMD3<Float>
    var angularVelocity: SIMD3<Float>
    /// Unit direction across the carpet.
    var direction: SIMD3<Float>

    static let gravity: Float = 9.81

    /// - Parameters:
    ///   - release: where the saqa leaves the hand.
    ///   - spot: the throw spot on the carpet; the throw is aimed from it at `target`.
    /// All of it with `SimMath`: this feeds the physics.
    init(input: ThrowInput, release: SIMD3<Float>, spot: SIMD3<Float>, target: SIMD3<Float>, arrival arrivalAngle: Float = GameTuning.Throw.arrivalAngle) {
        let up = SIMD3<Float>(0, 1, 0)
        var forward = target - spot
        forward.y = 0
        forward = SimMath.length(forward) > 0 ? SimMath.normalize(forward) : [0, 0, -1]
        let right = SimMath.cross(forward, up)
        let aim = SimMath.sinCos(input.angle)
        direction = forward * aim.cos + right * aim.sin

        // The technique: launched so that, at the speed that reaches the target, the saqa
        // comes down onto it at `arrivalAngle`, from any distance. Short throws come out
        // harder and flatter, long ones with a little loft, and every distance hits the kon
        // the same way (ADR-010).
        let height: Float = max(release.y, 0.01)
        let behind: Float = SimMath.dot(release - spot, direction)
        var toTarget = target - spot
        toTarget.y = 0
        let targetDistance = SimMath.length(toTarget)
        let reach: Float = max(targetDistance - behind, 0.3)
        let arrival = SimMath.sinCos(arrivalAngle)
        let squaredTime: Float = max(2 * (reach * arrival.sin / arrival.cos - height) / Self.gravity, 0.0025)
        let time = squaredTime.squareRoot()
        let along: Float = reach / time
        let rise: Float = Self.gravity * time / 2 - height / time
        let length: Float = (along * along + rise * rise).squareRoot()
        let cosine: Float = along / length
        let sine: Float = rise / length

        // Then the speed that lands on bare carpet `range` from the spot at that angle.
        let horizontal: Float = max(input.range(over: targetDistance) - behind, 0.2)
        let drop: Float = max(height + horizontal * (sine / cosine), 0.01)
        let denominator: Float = 2 * cosine * cosine * drop
        let speed: Float = (Self.gravity * horizontal * horizontal / denominator).squareRoot()

        position = release
        let heading: SIMD3<Float> = direction * cosine + up * sine
        linearVelocity = heading * speed
        let throwRight = SimMath.cross(direction, up)
        let tumble: SIMD3<Float> = throwRight * GameTuning.Throw.tumbleRate
        let sideSpin: SIMD3<Float> = up * (input.spin * GameTuning.Throw.maxSideSpin)
        angularVelocity = tumble + sideSpin
        // Held flat, buk up, the length pointing where it goes.
        rotation = SimMath.rotation(from: [1, 0, 0], to: direction)
    }

    /// Where the saqa leaves the hand when throwing from `spot` at `target`: low and just
    /// behind the line. Close in, the hand drops lower still, as a player kneels for a short
    /// throw: from too high a flat arrival can't be reached at all (`arrivalAngle`). A function
    /// of the spot and target alone, so the same input always starts the same way.
    static func releasePoint(spot: SIMD3<Float>, target: SIMD3<Float>, arrival arrivalAngle: Float = GameTuning.Throw.arrivalAngle) -> SIMD3<Float> {
        var toward = target - spot
        toward.y = 0
        let distance = SimMath.length(toward)
        toward = SimMath.normalize(toward)
        let behind: SIMD3<Float> = toward * GameTuning.Throw.releaseBehind
        let reach = distance + GameTuning.Throw.releaseBehind
        let arrival = SimMath.sinCos(arrivalAngle)
        // A level throw from height h comes down at tan α = 2h / reach.
        let height = min(GameTuning.Throw.releaseHeight, reach * arrival.sin / arrival.cos / 2)
        return spot - behind + SIMD3(0, height, 0)
    }

    /// Points along the flight, ignoring the carpet's bounce, until it reaches the ground.
    func trajectory(samples: Int) -> [SIMD3<Float>] {
        let vertical = linearVelocity.y
        // Time to fall from the release height to y = 0.
        let flightTime = (vertical + (vertical * vertical + 2 * Self.gravity * position.y).squareRoot()) / Self.gravity
        return (0...samples).map { index in
            let t = flightTime * Float(index) / Float(samples)
            var point = position + linearVelocity * t
            point.y -= 0.5 * Self.gravity * t * t
            return point
        }
    }
}
