import CoreGraphics
import Foundation
import Metal
import Observation
import QuartzCore
import simd

/// The M1 throw spike as a small game: throw at the kon, knock kenei out of the circle, keep
/// the series going from the circle's edge (Регламент, с. 63–66). Runs the frame loop: input →
/// physics → judge → camera → feel → draw. The full «Бес табан» rules arrive in M4.
@Observable
@MainActor
final class PracticeController {
    enum Call: Equatable {
        /// «Шықты!» and how many went out.
        case out(Int)
        /// «Тимеді».
        case miss
        /// Every kenei is out.
        case cleared
    }

    struct Banner: Equatable {
        var call: Call
        /// How the saqa came to rest, as the referee would call it.
        var saqaSide: Side?
        /// Changes on every throw, so the same call twice still animates.
        var serial: Int
    }

    // MARK: Interface state

    private(set) var banner: Banner?
    private(set) var knockedOut = 0
    private(set) var isFromEdge = false
    /// 0…1 while the finger is pulling, nil otherwise.
    private(set) var pullPower: Double?
    /// Where the saqa would land on bare carpet, meters from the spot.
    private(set) var pullRange: Float = 0
    private(set) var showsHint = true
    private(set) var framesPerSecond = 0
    let category: AgeCategory

    var throwDistance: Float {
        isFromEdge ? category.circleRadius : category.throwDistance
    }

    // MARK: Engine state

    private enum Phase {
        case aiming
        case flying(direction: SIMD3<Float>)
        case result(since: Double)
    }

    /// A kenei leaving the field after being knocked out: it glows, then shrinks away.
    private struct Departure {
        var pose: ArenaSimulation.Pose
        var scale = SpringValue(1)
        var startsAt: Double
    }

    /// A kenei sliding back onto its slot after a miss.
    private struct Return {
        var index: Int
        var from: ArenaSimulation.Pose
        var to: ArenaSimulation.Pose
        var progress = SpringValue(0)
        var startsAt: Double
    }

    @ObservationIgnored var reduceMotion = false
    /// Asks the view for frames again after it went idle.
    @ObservationIgnored var wake: (() -> Void)?

    @ObservationIgnored private let simulation: ArenaSimulation
    @ObservationIgnored private let renderer: ArenaRenderer?
    @ObservationIgnored private let haptics = HapticsDirector()
    @ObservationIgnored private var camera = ArenaCamera()
    @ObservationIgnored private var phase = Phase.aiming
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private var gesture: ThrowGesture?
    @ObservationIgnored private var lastTouch: Double = 0
    @ObservationIgnored private var handScale = SpringValue(1)
    /// 0 in the hand, 1 thrown: the swing that hands over to the real saqa.
    @ObservationIgnored private var handFlick = SpringValue(0)
    @ObservationIgnored private var sway = SpringValue(1)
    @ObservationIgnored private var aimVisibility = SpringValue(0)
    @ObservationIgnored private var timeScale = SpringValue(1)
    @ObservationIgnored private var slowMotionLeft: Float = 0
    @ObservationIgnored private var impactPoint: SIMD3<Float>?
    /// Simulated time of the first hit on the kon.
    @ObservationIgnored private var impactTime: Float = 0
    @ObservationIgnored private var hasHitKon = false
    @ObservationIgnored private var ripples: [(point: SIMD3<Float>, born: Double, strength: Float)] = []
    @ObservationIgnored private var departures: [Departure] = []
    @ObservationIgnored private var returns: [Return] = []
    @ObservationIgnored private var arrivals: [Int: SpringValue] = [:]
    @ObservationIgnored private var arrivalsStart: Double = 0
    @ObservationIgnored private var bannerSerial = 0
    @ObservationIgnored private var fpsWindow: (start: Double, frames: Int) = (0, 0)
    @ObservationIgnored private var debugThrow: ThrowInput?

    init(category: AgeCategory = .eresek) {
        self.category = category
        simulation = ArenaSimulation(category: category)
        renderer = try? ArenaRenderer()
        debugThrow = DebugLaunchArguments.throwInput
        if let pull = DebugLaunchArguments.pull {
            var frozen = ThrowGesture(start: .zero)
            frozen.current = CGPoint(x: -pull.aim * GameTuning.Gesture.fullAimPull, y: pull.power * GameTuning.Gesture.fullPull)
            gesture = frozen
            pullPower = frozen.power
            pullRange = frozen.input.range
            showsHint = false
        }
        if DebugLaunchArguments.fromEdge { isFromEdge = true }
        aimCamera(snap: true)
    }

    var metalDevice: MTLDevice? { renderer?.device }

    // MARK: - Geometry

    private var target: SIMD3<Float> { .zero }

    private var spot: SIMD3<Float> {
        [0, 0, throwDistance]
    }

    private var rowWidth: Float {
        Float(category.keneiCount - 1) * GameTuning.Field.keneiSpacing + 2 * BoneShape.kenei.halfExtents.x
    }

    private var releasePoint: SIMD3<Float> {
        ThrowLaunch.releasePoint(spot: spot, target: target)
    }

    // MARK: - Input

    var canThrow: Bool {
        if case .aiming = phase { return true }
        return false
    }

    func beginPull(at point: CGPoint) {
        guard canThrow else { return }
        gesture = ThrowGesture(start: point)
        lastTouch = clock
        pullPower = 0
        haptics.beginPull()
        wake?()
    }

    func updatePull(to point: CGPoint) {
        guard canThrow, var gesture else { return }
        gesture.current = point
        self.gesture = gesture
        lastTouch = clock
        pullPower = gesture.power
        pullRange = gesture.input.range
        haptics.updatePull(power: gesture.power)
    }

    func endPull(velocity: CGVector) {
        guard canThrow, let gesture else { return }
        self.gesture = nil
        pullPower = nil
        lastTouch = clock
        guard let input = gesture.release(velocity: velocity) else {
            haptics.cancelPull()
            return
        }
        haptics.release(power: Double(input.power))
        throwSaqa(input)
    }

    /// A fresh kon from the line, score cleared.
    func restart() {
        guard canThrow else { return }
        finishReturns()
        departures.removeAll()
        simulation.resetKon()
        arrivals = Dictionary(uniqueKeysWithValues: (0..<simulation.keneiCount).map { ($0, SpringValue(0)) })
        arrivalsStart = clock
        knockedOut = 0
        isFromEdge = false
        lastTouch = clock
        aimCamera(snap: reduceMotion)
        wake?()
    }

    private func throwSaqa(_ input: ThrowInput) {
        let launch = ThrowLaunch(input: input, release: releasePoint, spot: spot, target: target)
        simulation.throwSaqa(launch)
        phase = .flying(direction: launch.direction)
        handFlick.target = 1
        showsHint = false
        hasHitKon = false
        impactPoint = nil
        camera.spring = GameTuning.Camera.chaseSpring
        wake?()
    }

    // MARK: - Frame loop

    func resize(to size: CGSize) {
        camera.viewportSize = size
        if case .aiming = phase { aimCamera(snap: clock == 0) }
    }

    func frame(_ deltaTime: TimeInterval, layer: CAMetalLayer) -> FrameDemand {
        let dt = min(deltaTime, 1.0 / 20)
        clock += dt
        countFrame()
        runDebugThrow()

        if case .flying = phase {
            stepSlowMotion(dt)
            let hits = simulation.advance(realTime: dt, timeScale: Float(timeScale.value))
            handle(hits)
            if !simulation.isThrowInProgress { judge() }
        }
        if case .result(let since) = phase, clock - since >= GameTuning.Result.bannerTime {
            nextTurn()
        }

        updateCamera(dt)
        stepAnimations(dt)
        ripples.removeAll { clock - $0.born > 0.9 }

        if let renderer, camera.viewportSize.width > 1 {
            renderer.draw(makeScene(), in: layer)
        }
        return needsFrames ? .full : .none
    }

    private var needsFrames: Bool {
        if case .aiming = phase {
            return gesture != nil || !camera.isSettled || !handScale.isSettled || !sway.isSettled
                || !aimVisibility.isSettled || !ripples.isEmpty || !departures.isEmpty || !returns.isEmpty
                || !arrivals.isEmpty || clock - lastTouch < GameTuning.Hand.idleTimeout
        }
        return true
    }

    private func handle(_ hits: [ArenaSimulation.Hit]) {
        for hit in hits {
            if hit.isSaqaOnKenei {
                haptics.impact(hasHitKon ? .boneOnBone : .saqaOnKon, speed: hit.speed)
                if !hasHitKon {
                    hasHitKon = true
                    impactPoint = hit.point
                    impactTime = simulation.timeSinceThrow
                    if !reduceMotion, hit.speed >= GameTuning.SlowMotion.minImpactSpeed {
                        timeScale.value = Double(GameTuning.SlowMotion.scale)
                        timeScale.target = timeScale.value
                        slowMotionLeft = GameTuning.SlowMotion.holdSimTime
                    }
                }
            } else if hit.isOnCarpet {
                haptics.impact(.boneOnCarpet, speed: hit.speed)
                if hit.speed > GameTuning.Feel.rippleSpeed {
                    ripples.append((hit.point, clock, min(hit.speed / 5, 0.7)))
                    if ripples.count > 4 { ripples.removeFirst() }
                }
            } else {
                haptics.impact(.boneOnBone, speed: hit.speed)
            }
        }
    }

    private func stepSlowMotion(_ dt: Double) {
        if slowMotionLeft > 0 {
            slowMotionLeft -= Float(dt * timeScale.value)
            if slowMotionLeft <= 0 { timeScale.target = 1 }
        }
        timeScale.step(dt, GameTuning.SlowMotion.easeOut)
    }

    // MARK: - Judging

    private func judge() {
        timeScale.value = 1
        timeScale.target = 1
        slowMotionLeft = 0
        var knocked: [Int] = []
        var displaced: [Int] = []
        for index in 0..<simulation.keneiCount where simulation.isOnField(kenei: index) {
            guard let pose = simulation.pose(of: .kenei(index)) else { continue }
            if Judge.isKnockedOut(position: pose.position, rotation: pose.rotation, shape: .kenei, circleRadius: category.circleRadius) {
                knocked.append(index)
            } else if !isOnSlot(pose, index) {
                displaced.append(index)
            }
        }
        let saqaSide = simulation.pose(of: .saqa).map { PoseClassifier.side(of: $0.rotation, shape: .saqa) }

        for index in knocked {
            guard let pose = simulation.pose(of: .kenei(index)) else { continue }
            departures.append(Departure(pose: pose, startsAt: clock + 0.45))
            simulation.removeKenei(index)
        }
        knockedOut += knocked.count
        let remaining = (0..<simulation.keneiCount).filter { simulation.isOnField(kenei: $0) }.count

        let call: Call
        if remaining == 0 {
            call = .cleared
            haptics.knockedOut(count: 3)
        } else if knocked.isEmpty {
            call = .miss
            haptics.miss()
            // A miss puts the kenei back (Регламент, п. 1.3).
            for index in displaced {
                guard let pose = simulation.pose(of: .kenei(index)) else { continue }
                returns.append(Return(index: index, from: pose, to: simulation.slot(index), startsAt: clock + 0.55))
            }
        } else {
            call = .out(knocked.count)
            haptics.knockedOut(count: knocked.count)
        }
        bannerSerial += 1
        banner = Banner(call: call, saqaSide: saqaSide, serial: bannerSerial)
        phase = .result(since: clock)
        camera.spring = GameTuning.Camera.overviewSpring
        if reduceMotion { placeOverviewCamera(); camera.snap() }
    }

    private func isOnSlot(_ pose: ArenaSimulation.Pose, _ index: Int) -> Bool {
        let slot = simulation.slot(index)
        let moved = simd_distance(pose.position, slot.position)
        let turned = abs(simd_dot(pose.rotation.vector, slot.rotation.vector))
        return moved < 0.002 && turned > 0.9995
    }

    private func nextTurn() {
        let previousCall = banner?.call
        banner = nil
        simulation.removeSaqa()
        // A knock-out earns the next throw from the circle's edge; a miss sends you back to the line.
        switch previousCall {
        case .out: isFromEdge = true
        case .miss: isFromEdge = false
        case .cleared:
            isFromEdge = false
            simulation.resetKon()
            arrivals = Dictionary(uniqueKeysWithValues: (0..<simulation.keneiCount).map { ($0, SpringValue(0)) })
            arrivalsStart = clock
            knockedOut = 0
        case nil: break
        }
        finishReturns()
        phase = .aiming
        handFlick.value = 0
        handFlick.target = 0
        handScale.value = 0
        handScale.target = 1
        lastTouch = clock
        aimCamera(snap: reduceMotion)
    }

    // MARK: - Camera

    private func aimCamera(snap: Bool) {
        let shot = CameraShot.aim(spot: spot, target: target, rowWidth: rowWidth, aspect: camera.aspect)
        camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: shot.fieldOfView, spring: GameTuning.Camera.aimSpring)
        if snap { camera.snap() }
    }

    /// Frames the kon and everything that moved: kenei on their way out, the saqa if it's near.
    /// Anything far beyond the circle is clearly out; it's framed as if just past the line, so
    /// one wild kenei can't pull the camera to the far end of the hall.
    private func placeOverviewCamera() {
        let direction = SimMath.normalize(target - spot)
        let limit = category.circleRadius + 0.5
        func clamped(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let flat = SIMD2(point.x, point.z)
            let distance = simd_length(flat)
            guard distance > limit else { return point }
            let pulled = flat / distance * limit
            return SIMD3(pulled.x, point.y, pulled.y)
        }
        var points: [SIMD3<Float>] = [target]
        for index in 0..<simulation.keneiCount where simulation.isOnField(kenei: index) {
            guard let pose = simulation.renderPose(of: .kenei(index)) else { continue }
            if simd_distance(pose.position, simulation.slot(index).position) > 0.05 {
                points.append(clamped(pose.position))
            }
        }
        for departure in departures {
            points.append(clamped(departure.pose.position))
        }
        if let saqa = simulation.renderPose(of: .saqa), simd_length(SIMD2(saqa.position.x, saqa.position.z)) < limit {
            points.append(saqa.position)
        }
        let shot = CameraShot.frame(points: points, direction: direction, aspect: camera.aspect)
        camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: shot.fieldOfView, spring: GameTuning.Camera.overviewSpring)
    }

    private func updateCamera(_ dt: Double) {
        switch phase {
        case .aiming:
            break
        case .flying(let direction):
            let saqa = simulation.renderPose(of: .saqa)
            let passedKon = saqa.map { SimMath.dot($0.position - target, direction) > 0.4 } ?? false
            if reduceMotion {
                // No flying camera: hold the aim, then cut to the result.
                if hasHitKon || passedKon {
                    placeOverviewCamera()
                    camera.snap()
                }
                break
            }
            if let impactPoint, !reduceMotion, simulation.timeSinceThrow - impactTime < GameTuning.Camera.impactHold {
                let shot = CameraShot.impact(point: impactPoint, direction: direction, orbitSign: impactPoint.x >= 0 ? 1 : -1)
                camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: GameTuning.Camera.chaseFieldOfView * 1.15, spring: GameTuning.Camera.impactSpring)
            } else if hasHitKon || passedKon {
                // The hit is over: rise while things still roll, to watch kenei cross the line.
                placeOverviewCamera()
            } else if let saqa {
                let shot = CameraShot.chase(saqa: saqa.position, direction: direction, target: target)
                camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: GameTuning.Camera.chaseFieldOfView, spring: GameTuning.Camera.chaseSpring)
            }
        case .result:
            placeOverviewCamera()
        }
        camera.step(dt)
    }

    // MARK: - Animations

    private func stepAnimations(_ dt: Double) {
        handScale.step(dt, GameTuning.Result.knockedOutPop)
        handFlick.step(dt, GameTuning.Hand.flick)
        if handFlick.target == 1, handFlick.value > 0.97 {
            handScale.value = 0
            handScale.target = 0
        }
        sway.target = clock - lastTouch < GameTuning.Hand.idleTimeout ? 1 : 0
        sway.step(dt, SpringParameters(response: 1.2, dampingRatio: 1))
        aimVisibility.target = gesture == nil ? 0 : 1
        aimVisibility.step(dt, SpringParameters(response: 0.25, dampingRatio: 1))

        for index in departures.indices where clock >= departures[index].startsAt {
            departures[index].scale.target = 0
            departures[index].scale.step(dt, GameTuning.Result.knockedOutPop)
        }
        departures.removeAll { $0.scale.target == 0 && $0.scale.value < 0.01 }

        for index in returns.indices where clock >= returns[index].startsAt {
            returns[index].progress.target = 1
            returns[index].progress.step(dt, GameTuning.Result.restoreSpring)
        }
        let finished = returns.filter { $0.progress.isSettled && $0.progress.value == 1 }
        for item in finished {
            simulation.place(kenei: item.index, at: item.to)
        }
        returns.removeAll { $0.progress.isSettled && $0.progress.value == 1 }

        for key in arrivals.keys.sorted() {
            guard var spring = arrivals[key] else { continue }
            // A new kon grows in from the middle out.
            let fromMiddle = abs(Double(key) - Double(simulation.keneiCount - 1) / 2)
            if clock >= arrivalsStart + fromMiddle * 0.035 {
                spring.target = 1
                spring.step(dt, GameTuning.Result.knockedOutPop)
            }
            arrivals[key] = spring.isSettled && spring.value == 1 ? nil : spring
        }
    }

    /// A turn can start before a slow return ends; land them now.
    private func finishReturns() {
        for item in returns { simulation.place(kenei: item.index, at: item.to) }
        returns.removeAll()
    }

    // MARK: - Scene

    private func makeScene() -> ArenaRenderer.Scene {
        let boneColor = SIMD4(Palette.bone.linear, 0.32)
        var kenei: [ArenaRenderer.BoneInstance] = []
        var contacts: [SIMD4<Float>] = []
        let returning = Dictionary(uniqueKeysWithValues: returns.map { ($0.index, $0) })

        for index in 0..<simulation.keneiCount where simulation.isOnField(kenei: index) {
            guard var pose = simulation.renderPose(of: .kenei(index)) else { continue }
            if let item = returning[index] {
                let t = Float(min(max(item.progress.value, 0), 1.05))
                pose.position = simd_mix(item.from.position, item.to.position, SIMD3(repeating: t))
                pose.position.y += sin(min(t, 1) * .pi) * 0.05
                pose.rotation = simd_slerp(item.from.rotation, item.to.rotation, min(t, 1))
            }
            let scale = Float(arrivals[index]?.value ?? 1)
            kenei.append(.init(model: simd_float4x4(position: pose.position, rotation: pose.rotation, scale: scale), color: boneColor))
            contacts.append(SIMD4(pose.position, 0.022 * scale))
        }
        for departure in departures {
            let scale = Float(max(departure.scale.value, 0))
            var position = departure.pose.position
            position.y += (1 - scale) * 0.04
            let glow: Float = departure.scale.target == 0 ? 0.6 * scale : 0.8
            kenei.append(.init(model: simd_float4x4(position: position, rotation: departure.pose.rotation, scale: scale), color: boneColor, params: [0, glow, 0, 0]))
            contacts.append(SIMD4(position, 0.022 * scale))
        }

        let saqaColor = SIMD4(Palette.saqa.linear, 0.85)
        var saqa: [ArenaRenderer.BoneInstance] = []
        if let pose = simulation.renderPose(of: .saqa) {
            saqa.append(.init(model: simd_float4x4(position: pose.position, rotation: pose.rotation), color: saqaColor, params: [1, 0, 0, 0]))
            contacts.append(SIMD4(pose.position, 0.026))
        }

        var hand: [ArenaRenderer.BoneInstance] = []
        if handScale.value > 0.001 {
            hand.append(.init(model: handModel(), color: saqaColor, params: [1, 0, 0, 0]))
        }

        var field = ArenaRenderer.Field()
        field.circleRadius = category.circleRadius
        field.konHalfLength = category.konLength / 2
        field.nearThrowZ = category.throwDistance
        field.farThrowZ = -category.throwDistance
        field.contacts = contacts
        field.ripples = ripples.map { SIMD4($0.point.x, $0.point.z, Float((clock - $0.born) / 0.9), $0.strength) }

        // The aim guide runs along the carpet to where the saqa would land. An arc in the air
        // reads badly through the long lens: it seems to climb into the sky.
        if let gesture, gesture.isLongEnough {
            let launch = ThrowLaunch(input: gesture.input, release: releasePoint, spot: spot, target: target)
            if let landing = launch.trajectory(samples: GameTuning.Throw.previewSamples).last {
                field.aimFrom = SIMD2(spot.x, spot.z)
                field.aimTo = SIMD2(landing.x, landing.z)
            }
        }
        field.aimVisibility = Float(aimVisibility.value)
        field.landingRingRadius = 0.09

        let shadowFocus: SIMD3<Float>
        if case .flying = phase, let pose = simulation.renderPose(of: .saqa) {
            shadowFocus = simd_mix(pose.position, target, SIMD3(repeating: 0.5))
        } else {
            shadowFocus = simd_mix(spot, target, SIMD3(repeating: 0.55))
        }

        return ArenaRenderer.Scene(
            camera: camera,
            time: Float(clock.truncatingRemainder(dividingBy: 1000)),
            field: field,
            kenei: kenei,
            saqa: saqa,
            hand: hand,
            dots: [],
            shadowFocus: shadowFocus
        )
    }

    /// The saqa resting in the hand under the camera, drawn back by the pull.
    private func handModel() -> simd_float4x4 {
        let tuning = GameTuning.Hand.self
        let flick = Float(handFlick.value)
        let power = Float(gesture?.power ?? 0) * (1 - flick)
        let aim = Float(gesture?.aim ?? 0)
        let forward = camera.forward
        let up = camera.up
        let right = camera.right
        // Placed on screen rather than in the world, so it sits in the same spot whatever the lens.
        let distance = tuning.distance - tuning.pullBack * power
        let halfHeight = distance * tan(Float(camera.fieldOfView.value) / 2)
        let drop = halfHeight * (tuning.screenDrop + tuning.pullScreenDrop * power)
        var position = camera.eye.value + forward * (distance + flick * 0.45) - up * (drop + flick * 0.35) - right * (aim * 0.012)
        let swayPhase = Float(clock) * tuning.idleSwayRate * 2 * .pi
        let swayAmount = Float(sway.value) * (1 - power)
        position += up * sin(swayPhase * 0.5) * 0.003 * swayAmount

        var flat = forward
        flat.y = 0
        flat = simd_normalize(flat)
        let yaw = atan2(-flat.z, flat.x) + aim * GameTuning.Throw.maxAimAngle * -1.5
        let heading = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let idle = simd_quatf(angle: sin(swayPhase) * tuning.idleSwayAngle * swayAmount, axis: [0, 1, 0])
        let tilt = simd_quatf(angle: -0.5 * power - 0.25, axis: right)
        let rotation = tilt * idle * heading
        let spin = simd_quatf(angle: -flick * 2.4, axis: right)
        return simd_float4x4(position: position, rotation: spin * rotation, scale: Float(handScale.value))
    }

    // MARK: - Debug

    private func countFrame() {
        #if DEBUG
        fpsWindow.frames += 1
        if clock - fpsWindow.start >= 1 {
            framesPerSecond = Int((Double(fpsWindow.frames) / (clock - fpsWindow.start)).rounded())
            fpsWindow = (clock, 0)
        }
        #endif
    }

    private func runDebugThrow() {
        guard let input = debugThrow, clock > 1.2, canThrow else { return }
        debugThrow = nil
        gesture = nil
        pullPower = nil
        throwSaqa(input)
    }
}
