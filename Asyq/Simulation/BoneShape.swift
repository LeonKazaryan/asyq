import simd

/// The shape of one kind of bone, as both physics and the judge see it. Today a rounded box,
/// exactly what Jolt's `BoxShape` with a convex radius builds; scans replace it later (ADR-003).
struct BoneShape: Sendable {
    var halfExtents: SIMD3<Float>
    var cornerRadius: Float
    var mass: Float
    /// For each side, the bone's local direction that points straight up when it rests on that
    /// side. `PoseClassifier` picks the closest one.
    var upDirections: [(side: Side, local: SIMD3<Float>)]

    static let placeholderSides: [(side: Side, local: SIMD3<Float>)] = [
        (.alshy, [0, 0, 1]),
        (.taike, [0, 0, -1]),
        (.buk, [0, 1, 0]),
        (.shik, [0, -1, 0]),
        (.ompy, [1, 0, 0]),
        (.shonqai, [-1, 0, 0]),
    ]

    static let kenei = BoneShape(
        halfExtents: GameTuning.Bone.keneiHalfExtents,
        cornerRadius: GameTuning.Bone.keneiCornerRadius,
        mass: GameTuning.Bone.keneiMass,
        upDirections: placeholderSides
    )

    static let saqa = BoneShape(
        halfExtents: GameTuning.Bone.saqaHalfExtents,
        cornerRadius: GameTuning.Bone.saqaCornerRadius,
        mass: GameTuning.Bone.saqaMass,
        upDirections: placeholderSides
    )

    func localUp(for side: Side) -> SIMD3<Float> {
        upDirections.first { $0.side == side }?.local ?? [0, 1, 0]
    }

    /// The rotation that makes the bone rest on `side`, turned `yaw` about the vertical.
    func restingRotation(_ side: Side, yaw: Float = 0) -> simd_quatf {
        let tilt = SimMath.rotation(from: localUp(for: side), to: [0, 1, 0])
        guard yaw != 0 else { return tilt }
        return SimMath.multiply(SimMath.rotation(angle: yaw, axis: [0, 1, 0]), tilt)
    }

    /// Height of the center above the carpet when resting with `rotation`.
    func restingHeight(rotation: simd_quatf) -> Float {
        extent(along: [0, -1, 0], rotation: rotation)
    }

    /// How far the bone reaches from its center along a world `direction` (its support
    /// function). For a rounded box: the inner box's reach plus the rounding.
    func extent(along direction: SIMD3<Float>, rotation: simd_quatf) -> Float {
        let length = SimMath.length(direction)
        guard length > 0 else { return 0 }
        let local = SimMath.unrotate(direction / length, by: rotation)
        let inner = halfExtents - SIMD3(repeating: cornerRadius)
        return abs(local.x) * inner.x + abs(local.y) * inner.y + abs(local.z) * inner.z + cornerRadius
    }
}
