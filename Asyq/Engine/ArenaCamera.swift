import CoreGraphics
import simd

/// The scene camera. Eye, focus and lens all ride springs, so every cut between aiming,
/// chasing the saqa, the impact and the overview is a smooth, interruptible move.
struct ArenaCamera: Sendable {
    var eye = SpringVector([0, 1.25, 7])
    var focus = SpringVector([0, 0, 0])
    var fieldOfView = SpringValue(Double(30 * Float.pi / 180))
    var spring = GameTuning.Camera.aimSpring
    var viewportSize = CGSize(width: 1, height: 1)

    var aspect: Float {
        Float(max(viewportSize.width, 1) / max(viewportSize.height, 1))
    }

    var forward: SIMD3<Float> {
        simd_normalize(focus.value - eye.value)
    }

    var right: SIMD3<Float> {
        simd_normalize(simd_cross(forward, [0, 1, 0]))
    }

    var up: SIMD3<Float> {
        simd_cross(right, forward)
    }

    var view: simd_float4x4 {
        .lookAt(eye: eye.value, target: focus.value, up: [0, 1, 0])
    }

    var projection: simd_float4x4 {
        .perspective(
            fieldOfViewY: Float(fieldOfView.value),
            aspect: aspect,
            near: GameTuning.Camera.nearPlane,
            far: GameTuning.Camera.farPlane
        )
    }

    var viewProjection: simd_float4x4 {
        projection * view
    }

    var isSettled: Bool {
        eye.isSettled && focus.isSettled && fieldOfView.isSettled
    }

    mutating func aim(eye: SIMD3<Float>, focus: SIMD3<Float>, fieldOfView: Float, spring: SpringParameters) {
        self.eye.target = eye
        self.focus.target = focus
        self.fieldOfView.target = Double(fieldOfView)
        self.spring = spring
    }

    mutating func step(_ deltaTime: Double) {
        eye.step(deltaTime, spring)
        focus.step(deltaTime, spring)
        fieldOfView.step(deltaTime, spring)
    }

    mutating func snap() {
        eye.snap()
        focus.snap()
        fieldOfView.snap()
    }

    /// Projects a world point to view coordinates in points, top-left origin.
    func project(_ point: SIMD3<Float>) -> CGPoint? {
        let clip = viewProjection * SIMD4(point, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(
            x: CGFloat((ndc.x * 0.5 + 0.5)) * viewportSize.width,
            y: CGFloat((0.5 - ndc.y * 0.5)) * viewportSize.height
        )
    }
}

/// Where the camera goes for each moment of a throw.
enum CameraShot {
    /// Behind the thrower with a long lens, so the kon row spans most of the screen width.
    static func aim(spot: SIMD3<Float>, target: SIMD3<Float>, rowWidth: Float, aspect: Float) -> (eye: SIMD3<Float>, focus: SIMD3<Float>, fieldOfView: Float) {
        let tuning = GameTuning.Camera.self
        var toward = target - spot
        toward.y = 0
        toward = simd_normalize(toward)
        let eye = spot - toward * tuning.aimBack + SIMD3(0, tuning.aimHeight, 0)
        let focus = target + SIMD3(0, 0.02, 0)
        let distance = simd_length(focus - eye)
        let halfWidth = rowWidth / 2 / tuning.aimRowFill
        let tanHalfVertical = (halfWidth / distance) / max(aspect, 0.1)
        return (eye, focus, 2 * atan(tanHalfVertical))
    }

    /// Following the flying saqa from behind, holding back before the kon to frame the hit.
    static func chase(saqa: SIMD3<Float>, direction: SIMD3<Float>, target: SIMD3<Float>) -> (eye: SIMD3<Float>, focus: SIMD3<Float>) {
        let tuning = GameTuning.Camera.self
        var eye = saqa - direction * tuning.chaseBack + SIMD3(0, tuning.chaseHeight, 0)
        // Never past `chaseMinDistance` before the kon, measured along the throw.
        let before = simd_dot(target - eye, direction)
        if before < tuning.chaseMinDistance {
            eye += direction * (before - tuning.chaseMinDistance)
        }
        eye.y = max(eye.y, tuning.chaseHeight * 0.6)
        let ahead = saqa + direction * 0.6
        let focus = simd_mix(ahead, target, SIMD3(repeating: 0.45)) + SIMD3(0, -0.05, 0)
        return (eye, focus)
    }

    /// Swung round the first hit.
    static func impact(point: SIMD3<Float>, direction: SIMD3<Float>, orbitSign: Float) -> (eye: SIMD3<Float>, focus: SIMD3<Float>) {
        let tuning = GameTuning.Camera.self
        let swung = simd_quatf(angle: tuning.impactOrbit * orbitSign, axis: [0, 1, 0]).act(-direction)
        let eye = point + swung * tuning.impactDistance + SIMD3(0, tuning.impactHeight, 0)
        return (eye, point + SIMD3(0, 0.01, 0))
    }

    /// Frames everything that matters (the kon, kenei on the move, the saqa) from behind and
    /// above, as tight as they allow. Retargeted every frame, it pans with the action.
    static func frame(points: [SIMD3<Float>], direction: SIMD3<Float>, aspect: Float) -> (eye: SIMD3<Float>, focus: SIMD3<Float>, fieldOfView: Float) {
        let tuning = GameTuning.Camera.self
        guard let first = points.first else { return (SIMD3(0, 5, 4), .zero, tuning.overviewFieldOfView) }
        var low = SIMD2(first.x, first.z)
        var high = low
        for point in points {
            low = simd_min(low, SIMD2(point.x, point.z))
            high = simd_max(high, SIMD2(point.x, point.z))
        }
        let middle = (low + high) / 2
        let center = SIMD3(middle.x, 0, middle.y)
        var reach: Float = tuning.frameMinReach
        for point in points {
            reach = max(reach, simd_distance(SIMD2(point.x, point.z), middle) + tuning.frameMargin)
        }
        let distance = reach * tuning.frameDistance
        let eye = center - direction * (distance * cos(tuning.framePitch)) + SIMD3(0, distance * sin(tuning.framePitch), 0)
        // Aim a little past the middle, so the action sits low and the referee's call has room above.
        let focus = center + direction * (reach * 0.3)
        let tanHalfWidth = reach / distance
        let fieldOfView = 2 * atan(tanHalfWidth / max(aspect, 0.1))
        return (eye, focus, min(max(fieldOfView, tuning.frameMinFieldOfView), tuning.frameMaxFieldOfView))
    }

    /// High behind the circle, looking down on everything.
    static func overview(center: SIMD3<Float>, direction: SIMD3<Float>) -> (eye: SIMD3<Float>, focus: SIMD3<Float>) {
        let tuning = GameTuning.Camera.self
        let eye = center - direction * tuning.overviewBack + SIMD3(0, tuning.overviewHeight, 0)
        return (eye, center + direction * 0.3)
    }
}
