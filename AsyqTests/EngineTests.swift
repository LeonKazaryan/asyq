import simd
import Testing
@testable import Asyq

struct BoneMeshTests {
    @Test func theMeshIsExactlyTheRoundedBoxPhysicsSimulates() {
        let half = GameTuning.Bone.keneiHalfExtents
        let radius = GameTuning.Bone.keneiCornerRadius
        let mesh = BoneMesh.roundedBox(halfExtents: half, cornerRadius: radius)
        let inner = half - SIMD3(repeating: radius)
        for vertex in mesh.vertices {
            let position = SIMD3(vertex.position.x, vertex.position.y, vertex.position.z)
            // Every vertex lies exactly `radius` from the inner box: on the Minkowski surface.
            let nearest = simd_clamp(position, -inner, inner)
            #expect(abs(simd_distance(position, nearest) - radius) < 1e-5)
            #expect(all(simd_abs(position) .<= half + 1e-6))
        }
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.vertices.count < Int(UInt16.max))
    }

    @Test func trianglesFaceOutward() {
        let mesh = BoneMesh.roundedBox(halfExtents: [0.02, 0.01, 0.015], cornerRadius: 0.004)
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.vertices[Int(mesh.indices[triangle])].position
            let b = mesh.vertices[Int(mesh.indices[triangle + 1])].position
            let c = mesh.vertices[Int(mesh.indices[triangle + 2])].position
            let normal = simd_cross(SIMD3(b.x - a.x, b.y - a.y, b.z - a.z), SIMD3(c.x - a.x, c.y - a.y, c.z - a.z))
            let center = SIMD3(a.x + b.x + c.x, a.y + b.y + c.y, a.z + b.z + c.z) / 3
            guard simd_length(normal) > 1e-12 else { continue }
            #expect(simd_dot(normal, center) > 0)
        }
    }
}

struct SpringTests {
    @Test func aSpringSettlesOnItsTarget() {
        var spring = SpringValue(0)
        spring.target = 1
        for _ in 0..<240 { spring.step(1.0 / 120, SpringParameters(response: 0.4, dampingRatio: 0.9)) }
        #expect(spring.value == 1)
        #expect(spring.isSettled)
    }

    @Test func aBouncySpringOvershoots() {
        var spring = SpringValue(0)
        spring.target = 1
        var peak = 0.0
        for _ in 0..<120 {
            spring.step(1.0 / 120, SpringParameters(response: 0.4, dampingRatio: 0.4))
            peak = max(peak, spring.value)
        }
        #expect(peak > 1.05)
    }
}
