import simd

/// One move: everything the player decides in a throw. With the table's starting state it
/// determines the outcome exactly (docs/03-architecture.md, «Детерминизм»), so a turn can be
/// replayed, simulated by the bot, or later sent over the network as three numbers.
struct ThrowInput: Hashable, Sendable, Codable {
    /// Radians from straight at the kon, positive to the thrower's right.
    var angle: Float
    /// 0…1, where the saqa would land on bare carpet, from `minRange` to `maxRange`.
    var power: Float
    /// −1…1, side spin from the flick of the release.
    var spin: Float

    init(angle: Float, power: Float, spin: Float = 0) {
        let limit = GameTuning.Throw.maxAimAngle
        self.angle = min(max(angle, -limit), limit)
        self.power = min(max(power, 0), 1)
        self.spin = min(max(spin, -1), 1)
    }

    var range: Float {
        GameTuning.Throw.minRange + power * (GameTuning.Throw.maxRange - GameTuning.Throw.minRange)
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
    init(input: ThrowInput, release: SIMD3<Float>, spot: SIMD3<Float>, target: SIMD3<Float>, elevation elevationAngle: Float = GameTuning.Throw.launchElevation) {
        let up = SIMD3<Float>(0, 1, 0)
        var forward = target - spot
        forward.y = 0
        forward = SimMath.length(forward) > 0 ? SimMath.normalize(forward) : [0, 0, -1]
        let right = SimMath.cross(forward, up)
        let aim = SimMath.sinCos(input.angle)
        direction = forward * aim.cos + right * aim.sin

        // Solve the speed that lands on bare carpet `range` from the spot, at a fixed low
        // elevation, from the release height.
        let elevation = SimMath.sinCos(elevationAngle)
        let height: Float = max(release.y, 0.01)
        let behind: Float = SimMath.dot(release - spot, direction)
        let horizontal: Float = max(input.range - behind, 0.2)
        let rise: Float = height + horizontal * (elevation.sin / elevation.cos)
        let denominator: Float = 2 * elevation.cos * elevation.cos * rise
        let speed: Float = (Self.gravity * horizontal * horizontal / denominator).squareRoot()

        position = release
        let heading: SIMD3<Float> = direction * elevation.cos + up * elevation.sin
        linearVelocity = heading * speed
        let throwRight = SimMath.cross(direction, up)
        let tumble: SIMD3<Float> = throwRight * GameTuning.Throw.tumbleRate
        let sideSpin: SIMD3<Float> = up * (input.spin * GameTuning.Throw.maxSideSpin)
        angularVelocity = tumble + sideSpin
        // Held flat, buk up, the length pointing where it goes.
        rotation = SimMath.rotation(from: [1, 0, 0], to: direction)
    }

    /// Where the saqa leaves the hand when throwing from `spot` at `target`: low and just
    /// behind the line. A function of the spot alone, so the same input from the same spot
    /// always starts the same way.
    static func releasePoint(spot: SIMD3<Float>, target: SIMD3<Float>) -> SIMD3<Float> {
        var toward = target - spot
        toward.y = 0
        toward = SimMath.normalize(toward)
        let behind: SIMD3<Float> = toward * GameTuning.Throw.releaseBehind
        return spot - behind + SIMD3(0, GameTuning.Throw.releaseHeight, 0)
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
