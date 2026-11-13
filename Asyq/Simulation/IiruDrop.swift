import simd

/// How a saqa is spun onto the carpet in иіру: dropped from a little height, tumbling hard.
/// Like `ThrowLaunch`, all `SimMath`, so a spin is a replayable input.
struct IiruDrop: Sendable {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var linearVelocity: SIMD3<Float>
    var angularVelocity: SIMD3<Float>

    /// - Parameters:
    ///   - strength: 0…1, how hard the flick spun it.
    ///   - tilt: −1…1, which way the flick leaned: tips the spin axis.
    init(at center: SIMD3<Float>, strength: Float, tilt: Float) {
        let tuning = GameTuning.Iiru.self
        let strength = min(max(strength, 0), 1)
        let tilt = min(max(tilt, -1), 1)
        position = center + SIMD3(0, tuning.dropHeight, 0)
        // Held flat in the fingers, then spun mostly about its length, as the hand does it.
        rotation = SimMath.rotation(angle: tilt * 0.6, axis: [0, 1, 0])
        let axis = SimMath.normalize(SIMD3(1, tilt * 0.35, 0.25 + 0.2 * tilt))
        let rate = tuning.minSpin + strength * (tuning.maxSpin - tuning.minSpin)
        angularVelocity = axis * rate + SIMD3(0, tuning.twist * (0.5 + tilt), 0)
        linearVelocity = SIMD3(tilt * 0.25, -tuning.dropSpeed, -0.15)
    }
}
