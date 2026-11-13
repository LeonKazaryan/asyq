import simd

/// Camera matrices for Metal: right-handed world, clip-space depth 0…1.
extension simd_float4x4 {
    static func perspective(fieldOfViewY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fieldOfViewY / 2)
        let xs = ys / aspect
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, -1),
            SIMD4(0, 0, zs * near, 0)
        ))
    }

    static func orthographic(halfWidth: Float, halfHeight: Float, near: Float, far: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1 / halfWidth, 0, 0, 0),
            SIMD4(0, 1 / halfHeight, 0, 0),
            SIMD4(0, 0, 1 / (near - far), 0),
            SIMD4(0, 0, near / (near - far), 1)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(target - eye)
        let side = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(side, forward)
        return simd_float4x4(columns: (
            SIMD4(side.x, trueUp.x, -forward.x, 0),
            SIMD4(side.y, trueUp.y, -forward.y, 0),
            SIMD4(side.z, trueUp.z, -forward.z, 0),
            SIMD4(-simd_dot(side, eye), -simd_dot(trueUp, eye), simd_dot(forward, eye), 1)
        ))
    }

    /// Rotation, then uniform scale, then translation.
    init(position: SIMD3<Float>, rotation: simd_quatf, scale: Float = 1) {
        var matrix = simd_float4x4(rotation)
        matrix.columns.0 *= scale
        matrix.columns.1 *= scale
        matrix.columns.2 *= scale
        matrix.columns.3 = SIMD4(position, 1)
        self = matrix
    }
}
