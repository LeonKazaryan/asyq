import simd

/// Tells which side a resting bone lies on: the side whose "up" direction is closest to the
/// real up (docs/03-architecture.md, «Форма кости и стороны»).
enum PoseClassifier {
    static func side(of rotation: simd_quatf, shape: BoneShape) -> Side {
        let up = SimMath.unrotate([0, 1, 0], by: rotation)
        var best = shape.upDirections[0]
        var bestDot = -Float.infinity
        for candidate in shape.upDirections {
            let dot = SimMath.dot(up, candidate.local)
            if dot > bestDot {
                bestDot = dot
                best = candidate
            }
        }
        return best.side
    }
}
