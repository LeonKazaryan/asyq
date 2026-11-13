import AsyqPhysics
import simd

/// Arithmetic for everything that feeds the simulation or judges its result: throw velocities,
/// starting poses, which side a bone lies on, whether a kenei is out. Plain Swift `+ - * /`
/// and `squareRoot()` are exact IEEE operations, and the trig comes from Jolt. simd's C helpers
/// (`simd_normalize`, `act`, quaternion `*`) and libm's `sin`/`cos` are not: clang fuses them
/// differently in Debug and Release, and libm may change between iOS versions. One different
/// bit would let the same throw end differently on two phones. Rendering may use anything.
enum SimMath {
    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ v: SIMD3<Float>) -> Float {
        dot(v, v).squareRoot()
    }

    static func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        DeterministicMath.normalize(v)
    }

    static func sinCos(_ angle: Float) -> (sin: Float, cos: Float) {
        DeterministicMath.sinCos(angle)
    }

    static func rotation(angle: Float, axis: SIMD3<Float>) -> simd_quatf {
        DeterministicMath.rotation(angle: angle, axis: axis)
    }

    /// `a * b`: first `b`, then `a`.
    static func multiply(_ a: simd_quatf, _ b: simd_quatf) -> simd_quatf {
        let av = a.imag
        let bv = b.imag
        let real = a.real * b.real - dot(av, bv)
        let imag = bv * a.real + av * b.real + cross(av, bv)
        return simd_quatf(ix: imag.x, iy: imag.y, iz: imag.z, r: real)
    }

    static func rotate(_ v: SIMD3<Float>, by q: simd_quatf) -> SIMD3<Float> {
        let u = q.imag
        let t = cross(u, v) * 2
        return v + t * q.real + cross(u, t)
    }

    /// From world into the frame of a body rotated by `q` (a unit quaternion).
    static func unrotate(_ v: SIMD3<Float>, by q: simd_quatf) -> SIMD3<Float> {
        rotate(v, by: simd_quatf(ix: -q.imag.x, iy: -q.imag.y, iz: -q.imag.z, r: q.real))
    }

    /// The shortest turn taking direction `from` onto `to`.
    static func rotation(from: SIMD3<Float>, to: SIMD3<Float>) -> simd_quatf {
        let f = normalize(from)
        let t = normalize(to)
        let d = dot(f, t)
        if d < -0.99999 {
            // Opposite: half a turn about any axis square to `from`.
            var axis = cross(f, [1, 0, 0])
            if dot(axis, axis) < 1e-6 { axis = cross(f, [0, 1, 0]) }
            axis = normalize(axis)
            return simd_quatf(ix: axis.x, iy: axis.y, iz: axis.z, r: 0)
        }
        let c = cross(f, t)
        let s = ((1 + d) * 2).squareRoot()
        return simd_quatf(ix: c.x / s, iy: c.y / s, iz: c.z / s, r: s / 2)
    }
}
