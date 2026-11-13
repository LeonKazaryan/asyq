import simd

/// Where on the field each `ThrowSpot` is: where the thrower stands and what they aim at
/// (docs/05-rules.md, §3). This sets a throw's starting state, so it's all `SimMath`.
enum ThrowSpotGeometry {
    /// - Parameter kenei: where the target kenei lies, for special throws. Without it a special
    ///   spot falls back to the circle's edge.
    static func place(_ spot: ThrowSpot, thrower: Player, category: AgeCategory, kenei: SIMD3<Float>?) -> (spot: SIMD3<Float>, target: SIMD3<Float>) {
        let center = SIMD3<Float>(0, 0, 0)
        let side: Float = thrower == .home ? 1 : -1
        let radius = category.circleRadius
        let edge = SIMD3<Float>(0, 0, side * radius)

        switch spot {
        case .line:
            return ([0, 0, side * category.throwDistance], center)
        case .circleEdge:
            return (edge, center)
        case .besTaban(_, let flank):
            guard let kenei, let direction = flatDirection(kenei) else { return (edge, center) }
            // Five tabans of arc along the circle from the kenei's bearing (каз. п. 2.1).
            let angle = 5 * GameTuning.Rules.taban / radius
            let turned = rotate(direction, by: flank == .left ? angle : -angle)
            return (SIMD3(turned.x * radius, 0, turned.y * radius), kenei)
        case .diagonal:
            // The circle's far side from the kenei, so the throw crosses the kon, as on the
            // Регламент's diagram (с. 25).
            guard let kenei, let direction = flatDirection(kenei) else { return (edge, center) }
            return (SIMD3(-direction.x * radius, 0, -direction.y * radius), kenei)
        case .parallel(_, let flank):
            // The circle's wing on the kon's axis (каз. п. 2.3).
            guard let kenei else { return (edge, center) }
            return (SIMD3(flank == .left ? -radius : radius, 0, 0), kenei)
        }
    }

    /// The default side for «Бес табан» and «Параллель»: the spot nearer the kenei. Both
    /// «Бес табан» spots are always equally far from it, so there the thrower's own half of the
    /// field wins: less walking. Ties go right.
    static func nearestFlank(for spot: ThrowSpot, thrower: Player, category: AgeCategory, kenei: SIMD3<Float>) -> Flank {
        let left: ThrowSpot
        let right: ThrowSpot
        switch spot {
        case .besTaban(let index, _):
            left = .besTaban(kenei: index, flank: .left)
            right = .besTaban(kenei: index, flank: .right)
        case .parallel(let index, _):
            left = .parallel(kenei: index, flank: .left)
            right = .parallel(kenei: index, flank: .right)
        case .line, .circleEdge, .diagonal:
            return .right
        }
        let leftSpot = place(left, thrower: thrower, category: category, kenei: kenei).spot
        let rightSpot = place(right, thrower: thrower, category: category, kenei: kenei).spot
        let leftDistance = squaredFlatDistance(leftSpot, kenei)
        let rightDistance = squaredFlatDistance(rightSpot, kenei)
        // Distances that differ only by rounding count as equal.
        let tolerance: Float = 1e-6
        if leftDistance < rightDistance - tolerance { return .left }
        if rightDistance < leftDistance - tolerance { return .right }
        let side: Float = thrower == .home ? 1 : -1
        return leftSpot.z * side > rightSpot.z * side + tolerance ? .left : .right
    }

    // MARK: - Plane math on (x, z)

    /// The unit direction of a point's (x, z) from the center; nil at the center itself.
    private static func flatDirection(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        let length = (point.x * point.x + point.z * point.z).squareRoot()
        guard length > 1e-4 else { return nil }
        return SIMD2(point.x / length, point.z / length)
    }

    /// Turns an (x, z) direction by `angle` about the vertical: positive is counterclockwise
    /// seen from above (y up, x right, z toward the viewer's bottom), so +x turns toward −z.
    private static func rotate(_ direction: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let (sine, cosine) = SimMath.sinCos(angle)
        return SIMD2(
            direction.x * cosine + direction.y * sine,
            -direction.x * sine + direction.y * cosine
        )
    }

    private static func squaredFlatDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}
