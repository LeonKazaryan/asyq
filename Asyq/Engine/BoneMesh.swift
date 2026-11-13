import simd

/// Mirrors `BoneVertex` in ArenaShaders.metal.
struct BoneVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
}

/// A rounded box mesh: an inner box grown by `cornerRadius` in every direction, the same
/// shape Jolt simulates for a `BoxShape` with that convex radius. So what you see is exactly
/// what collides.
enum BoneMesh {
    static func roundedBox(halfExtents: SIMD3<Float>, cornerRadius: Float, roundingSteps: Int = 6) -> (vertices: [BoneVertex], indices: [UInt16]) {
        let inner = halfExtents - SIMD3(repeating: cornerRadius)
        var vertices: [BoneVertex] = []
        var indices: [UInt16] = []

        // Along one face axis: two flat segments in the middle, and the rounding sampled
        // evenly in angle (offset r·tan φ for φ up to 45°, where the neighbouring face takes over).
        func samples(_ innerHalf: Float) -> [Float] {
            let rounding = (1...roundingSteps).map { step in
                cornerRadius * tan(Float(step) / Float(roundingSteps) * .pi / 4)
            }
            let flat: [Float] = [-innerHalf, 0, innerHalf]
            return rounding.reversed().map { -innerHalf - $0 } + flat + rounding.map { innerHalf + $0 }
        }

        for axis in 0..<3 {
            for sign: Float in [1, -1] {
                let uAxis = (axis + 1) % 3
                let vAxis = (axis + 2) % 3
                let us = samples(inner[uAxis])
                let vs = samples(inner[vAxis])
                let base = vertices.count
                for v in vs {
                    for u in us {
                        var onBox = SIMD3<Float>(repeating: 0)
                        onBox[axis] = sign * halfExtents[axis]
                        onBox[uAxis] = u
                        onBox[vAxis] = v
                        let core = simd_clamp(onBox, -inner, inner)
                        let normal = simd_normalize(onBox - core)
                        let position = core + normal * cornerRadius
                        vertices.append(BoneVertex(position: SIMD4(position, 1), normal: SIMD4(normal, 0)))
                    }
                }
                let columns = us.count
                for row in 0..<(vs.count - 1) {
                    for column in 0..<(columns - 1) {
                        let a = base + row * columns + column
                        let b = a + 1
                        let c = a + columns
                        let d = c + 1
                        // Wind counter-clockwise seen from outside, whichever way the face points.
                        let pa = vertices[a].position, pb = vertices[b].position, pc = vertices[c].position
                        let faceNormal = simd_cross(SIMD3(pb.x - pa.x, pb.y - pa.y, pb.z - pa.z), SIMD3(pc.x - pa.x, pc.y - pa.y, pc.z - pa.z))
                        let outward = simd_dot(faceNormal, SIMD3(vertices[a].normal.x, vertices[a].normal.y, vertices[a].normal.z)) > 0
                        let quad = outward ? [a, b, c, b, d, c] : [a, c, b, b, c, d]
                        indices.append(contentsOf: quad.map { UInt16($0) })
                    }
                }
            }
        }
        return (vertices, indices)
    }
}
