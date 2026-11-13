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
}
