import simd

/// Turns where the bones came to rest into facts the rules work with.
enum Judge {
    /// Регламент: a kenei counts only once it is beyond the circle's outer line.
    /// docs/05-rules.md, question 6 (🟡): the whole bone must be past the line's outer edge.
    static func isKnockedOut(
        position: SIMD3<Float>,
        rotation: simd_quatf,
        shape: BoneShape,
        circleRadius: Float,
        lineWidth: Float = FieldGeometry.circleLineWidth
    ) -> Bool {
        let flat = SIMD3<Float>(position.x, 0, position.z)
        let distance = SimMath.length(flat)
        guard distance > 0 else { return false }
        // The bone's nearest reach back toward the center, measured along the radius. Exact
        // enough for a 3 cm bone on a 2.5 m circle.
        let inward = -flat / distance
        let nearest = distance - shape.extent(along: inward, rotation: rotation)
        return nearest > circleRadius + lineWidth / 2
    }

    /// Where a kenei that moved but stayed in the circle lies, which decides the referee's
    /// command (docs/05-rules.md, §3, «Особые команды»). Checked in order: between the
    /// parallel lines along the kon (п. 2.3), within a taban of the circle line (каз. п. 2.1),
    /// anywhere else (п. 2.2). Judged by the bone's center.
    static func zone(of position: SIMD3<Float>, category: AgeCategory) -> KeneiZone {
        if abs(position.z) <= FieldGeometry.parallelLineOffset, abs(position.x) <= category.konLength / 2 {
            return .parallel
        }
        let distance = SimMath.length(SIMD3(position.x, 0, position.z))
        if distance >= category.circleRadius - GameTuning.Rules.taban {
            return .nearCircle
        }
        return .middle
    }

    /// «Сырғытпа» (п. 1.5.2): the saqa came at the circle sliding along the carpet, landing
    /// before it reached the circle. 🟡 Formally (docs/05-rules.md): its first touch of the
    /// carpet, before touching any kenei, is outside the circle on the thrower's side. A throw
    /// that sails over everything and lands beyond the far side is just a miss.
    static func isSlide(landing: SIMD3<Float>, spot: SIMD3<Float>, target: SIMD3<Float>, category: AgeCategory) -> Bool {
        let flat = SIMD3<Float>(landing.x, 0, landing.z)
        guard SimMath.length(flat) > category.circleRadius + FieldGeometry.circleLineWidth / 2 else { return false }
        var toward = target - spot
        toward.y = 0
        // Short of the target, seen along the throw.
        return SimMath.dot(flat - SIMD3(target.x, 0, target.z), SimMath.normalize(toward)) < 0
    }
}
