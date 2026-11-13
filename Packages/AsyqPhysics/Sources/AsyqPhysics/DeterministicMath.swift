import CJolt
import simd

/// Math for values that go into the simulation, such as a throw's velocity and spin.
///
/// The physics is bit-identical everywhere, but only if its inputs are too. Two things break
/// that quietly: libm's `sin`/`cos`, which may differ between OS versions, and simd's C
/// helpers (`simd_quatf(angle:axis:)`, `simd_normalize`, `act`), which clang compiles into the
/// caller with fused multiply-add, so Debug and Release round them differently. Plain Swift
/// `+ - * /` and `squareRoot()` are exact IEEE operations and safe.
public enum DeterministicMath {
    public static func sinCos(_ angle: Float) -> (sin: Float, cos: Float) {
        var sine: Float = 0
        var cosine: Float = 0
        ap_sin_cos(angle, &sine, &cosine)
        return (sine, cosine)
    }

    public static func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        return length > 0 ? v / length : v
    }

    /// `angle` radians around `axis` (normalized here).
    public static func rotation(angle: Float, axis: SIMD3<Float>) -> simd_quatf {
        let unit = normalize(axis)
        let (sine, cosine) = sinCos(angle / 2)
        return simd_quatf(ix: unit.x * sine, iy: unit.y * sine, iz: unit.z * sine, r: cosine)
    }
}
