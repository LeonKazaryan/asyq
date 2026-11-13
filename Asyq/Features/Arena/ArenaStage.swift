import CoreGraphics
import Foundation
import Metal
import Observation
import QuartzCore
import simd

/// The arena as a stage for any game mode: physics, camera, animations, the hand and its
/// slingshot, иіру, and drawing. A mode (practice, a «Бес табан» match) tells it where the
/// next throw comes from and what to do with the kenei; the stage reports what happened.
@Observable
@MainActor
final class ArenaStage {
    /// Where a throw comes from and what it's aimed at.
    struct Aim: Equatable {
        var spot: SIMD3<Float>
        var target: SIMD3<Float>
        /// How wide the thing aimed at is: the kon row, or one kenei. Sets the lens.
        var framingWidth: Float
        /// Whose saqa throws: the hand and the slingshot belong to the home player.
        var thrower: Player
        /// The landing preview while pulling.
        var showsGuide = true
        /// The kenei a special throw is aimed at: it glows.
        var targetKenei: Int?
    }

    enum Event {
        /// A throw came to rest: what the judge saw, and how the saqa lies.
        case settled(ThrowFacts, saqaSide: Side?)
        /// Both iiru saqas came to rest.
        case iiruSettled([Player: Side])
    }

    // MARK: Observed by the HUD

    /// 0…1 while the finger pulls, nil otherwise.
    private(set) var pullPower: Double?
    /// Where the saqa would land on bare carpet, meters from the spot.
    private(set) var pullRange: Float = 0
    private(set) var framesPerSecond = 0
    /// The current aim, nil between turns.
    private(set) var aim: Aim?

    // MARK: Wiring

    let category: AgeCategory
    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored var reduceMotion = false
    /// Asks the view for frames again after it went idle.
    @ObservationIgnored var wake: (() -> Void)?

    var metalDevice: MTLDevice? { renderer?.device }

    // MARK: Engine state

    private enum Shot {
        case aim
        case flight(direction: SIMD3<Float>)
        case result
        case iiru
    }

    /// A kenei leaving the field after being knocked out: it glows, then shrinks away.
    private struct Departure {
        var pose: ArenaSimulation.Pose
        var scale = SpringValue(1)
        var startsAt: Double
    }

    /// A kenei sliding back onto its slot.
    private struct Return {
        var index: Int
        var from: ArenaSimulation.Pose
        var to: ArenaSimulation.Pose
        var progress = SpringValue(0)
        var startsAt: Double
    }

    @ObservationIgnored private let simulation: ArenaSimulation
    @ObservationIgnored private let renderer: ArenaRenderer?
    @ObservationIgnored private let haptics = HapticsDirector()
    @ObservationIgnored private var camera = ArenaCamera()
    /// Observed: whether the slingshot works hangs on it.
    private var shot = Shot.aim
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private var gesture: ThrowGesture?
    @ObservationIgnored private var lastTouch: Double = 0
    @ObservationIgnored private var handScale = SpringValue(0)
    /// 0 in the hand, 1 thrown: the swing that hands over to the real saqa.
    @ObservationIgnored private var handFlick = SpringValue(0)
    @ObservationIgnored private var sway = SpringValue(1)
    @ObservationIgnored private var aimVisibility = SpringValue(0)
    @ObservationIgnored private var timeScale = SpringValue(1)
    @ObservationIgnored private var slowMotionLeft: Float = 0
    @ObservationIgnored private var saqaOwner = Player.home
    @ObservationIgnored private var hits = ThrowRecord()
    @ObservationIgnored private var ripples: [(point: SIMD3<Float>, born: Double, strength: Float)] = []
    @ObservationIgnored private var departures: [Departure] = []
    @ObservationIgnored private var returns: [Return] = []
    @ObservationIgnored private var arrivals: [Int: SpringValue] = [:]
    @ObservationIgnored private var arrivalsStart: Double = 0
    @ObservationIgnored private var fpsWindow: (start: Double, frames: Int) = (0, 0)
    @ObservationIgnored private var iiruSpinning: Set<Player> = []
    @ObservationIgnored private var iiruFocus = SpringVector(.zero)

    /// What the saqa did in the throw under way.
    private struct ThrowRecord {
        var hitKon = false
        var impactPoint: SIMD3<Float>?
        var impactTime: Float = 0
        /// Where the saqa first touched the carpet, if before it touched any kenei.
        var firstLanding: SIMD3<Float>?
        /// Kenei the saqa itself touched, first first.
        var touched: [Int] = []
    }

    init(category: AgeCategory) {
        self.category = category
        simulation = ArenaSimulation(category: category)
        renderer = try? ArenaRenderer()
    }

    // MARK: - The kon

    var keneiCount: Int { simulation.keneiCount }

    func isOnField(kenei index: Int) -> Bool {
        simulation.isOnField(kenei: index)
    }

    func position(ofKenei index: Int) -> SIMD3<Float>? {
        simulation.pose(of: .kenei(index))?.position
    }

    /// A full kon again. Animated, the kenei grow onto their slots from the middle out.
    func resetKon(animated: Bool) {
        finishReturns()
        departures.removeAll()
        simulation.removeSaqa()
        simulation.resetKon()
        arrivals = animated ? Dictionary(uniqueKeysWithValues: (0..<simulation.keneiCount).map { ($0, SpringValue(0)) }) : [:]
        arrivalsStart = clock
        wake?()
    }

    /// Knocked-out kenei leave: a glow, then they shrink away.
    func remove(kenei indices: [Int]) {
        for index in indices {
            guard let pose = simulation.pose(of: .kenei(index)) else { continue }
            departures.append(Departure(pose: pose, startsAt: clock + 0.45))
            simulation.removeKenei(index)
        }
        wake?()
    }

    /// Moved kenei slide back onto their slots (Регламент, п. 1.3).
    func restore(kenei indices: [Int]) {
        for index in indices {
            guard let pose = simulation.pose(of: .kenei(index)), !isOnSlot(pose, index) else { continue }
            returns.append(Return(index: index, from: pose, to: simulation.slot(index), startsAt: clock + 0.5))
        }
        wake?()
    }

    // MARK: - Aiming and throwing

    var canPull: Bool {
        guard let aim, case .aim = shot else { return false }
        return aim.thrower == .home
    }

    /// Sets up the next throw: the camera goes behind the thrower; for the home player the
    /// saqa appears in the hand.
    func aim(_ aim: Aim) {
        self.aim = aim
        shot = .aim
        simulation.removeSaqa()
        finishReturns()
        gesture = nil
        pullPower = nil
        saqaOwner = aim.thrower
        handFlick.value = 0
        handFlick.target = 0
        handScale.target = aim.thrower == .home ? 1 : 0
        lastTouch = clock
        aimCamera(snap: reduceMotion)
        wake?()
    }

    func beginPull(at point: CGPoint) {
        guard canPull else { return }
        gesture = ThrowGesture(start: point)
        lastTouch = clock
        pullPower = 0
        haptics.beginPull()
        wake?()
    }

    func updatePull(to point: CGPoint) {
        guard canPull, var gesture, let aim else { return }
        gesture.current = point
        self.gesture = gesture
        lastTouch = clock
        pullPower = gesture.power
        pullRange = gesture.input.range(over: flatDistance(aim.spot, aim.target))
        haptics.updatePull(power: gesture.power)
    }

    /// Lets go: throws, or cancels a pull too short to mean it.
    func endPull(velocity: CGVector) {
        guard canPull, let gesture else { return }
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

    /// Throws from the current aim: the home player's release, or the bot's choice.
    func throwSaqa(_ input: ThrowInput) {
        guard let aim, case .aim = shot else { return }
        finishReturns()
        let launch = ThrowLaunch(
            input: input,
            release: ThrowLaunch.releasePoint(spot: aim.spot, target: aim.target),
            spot: aim.spot,
            target: aim.target
        )
        simulation.throwSaqa(launch)
        shot = .flight(direction: launch.direction)
        hits = ThrowRecord()
        handFlick.target = 1
        camera.spring = GameTuning.Camera.chaseSpring
        wake?()
    }

    private func flatDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(SIMD2(a.x - b.x, a.z - b.z))
    }

    // MARK: - Иіру

    /// Where the iiru saqas land: beside the circle, home side.
    private var iiruCenter: SIMD3<Float> {
        [GameTuning.Iiru.offAxis, 0, category.circleRadius + GameTuning.Iiru.besideCircle]
    }

    /// Moves the camera down to the carpet beside the circle for иіру.
    func beginIiru() {
        aim = nil
        shot = .iiru
        simulation.removeSaqa()
        simulation.removeIiru()
        iiruSpinning = []
        handScale.target = 0
        iiruFocus = SpringVector(iiruCenter)
        placeIiruCamera()
        if reduceMotion { camera.snap() }
        wake?()
    }

    /// Spins one player's saqa onto the carpet.
    func spinIiru(_ player: Player, strength: Float, tilt: Float) {
        guard case .iiru = shot else { return }
        let side: Float = player == .home ? -1 : 1
        let center = iiruCenter + SIMD3(side * GameTuning.Iiru.spacing / 2, 0, 0)
        simulation.spin(player, IiruDrop(at: center, strength: strength, tilt: tilt))
        iiruSpinning.insert(player)
        if player == .home { haptics.release(power: Double(strength)) }
        wake?()
    }

    func endIiru() {
        simulation.removeIiru()
        iiruSpinning = []
    }

    private func placeIiruCamera() {
        let focus = iiruFocus.value
        let eye = focus + SIMD3(0, 0.26, 0.36)
        camera.aim(eye: eye, focus: focus, fieldOfView: 34 * .pi / 180, spring: GameTuning.Camera.aimSpring)
    }

    // MARK: - Frame loop

    func resize(to size: CGSize) {
        camera.viewportSize = size
        if case .aim = shot, aim != nil { aimCamera(snap: clock == 0) }
    }

    func frame(_ deltaTime: TimeInterval, layer: CAMetalLayer) -> FrameDemand {
        let dt = min(deltaTime, 1.0 / 20)
        clock += dt
        countFrame()

        if simulation.isThrowInProgress {
            stepSlowMotion(dt)
            let newHits = simulation.advance(realTime: dt, timeScale: Float(timeScale.value))
            handle(newHits)
            if !simulation.isThrowInProgress { settle() }
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
        if simulation.isThrowInProgress { return true }
        switch shot {
        case .flight, .iiru: return true
        case .aim, .result:
            return gesture != nil || !camera.isSettled || !handScale.isSettled || !handFlick.isSettled
                || !sway.isSettled || !aimVisibility.isSettled || !ripples.isEmpty || !departures.isEmpty
                || !returns.isEmpty || !arrivals.isEmpty
                || (aim?.thrower == .home && clock - lastTouch < GameTuning.Hand.idleTimeout)
        }
    }

    private func handle(_ newHits: [ArenaSimulation.Hit]) {
        for hit in newHits {
            if hit.isSaqaOnKenei {
                haptics.impact(hits.hitKon ? .boneOnBone : .saqaOnKon, speed: hit.speed)
                for piece in [hit.first, hit.second] {
                    if case .kenei(let index) = piece, !hits.touched.contains(index) {
                        hits.touched.append(index)
                    }
                }
                if !hits.hitKon {
                    hits.hitKon = true
                    hits.impactPoint = hit.point
                    hits.impactTime = simulation.timeSinceThrow
                    if !reduceMotion, hit.speed >= GameTuning.SlowMotion.minImpactSpeed {
                        timeScale.value = Double(GameTuning.SlowMotion.scale)
                        timeScale.target = timeScale.value
                        slowMotionLeft = GameTuning.SlowMotion.holdSimTime
                    }
                }
            } else if hit.isOnCarpet {
                // Only a landing before the saqa reached the kon can be a slide.
                if hit.involves(.saqa), hits.firstLanding == nil, !hits.hitKon {
                    hits.firstLanding = hit.point
                }
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

    // MARK: - Settling

    private func settle() {
        timeScale.value = 1
        timeScale.target = 1
        slowMotionLeft = 0
        if case .iiru = shot {
            settleIiru()
            return
        }
        shot = .result
        camera.spring = GameTuning.Camera.overviewSpring
        if reduceMotion {
            placeOverviewCamera()
            camera.snap()
        }
        let saqaSide = simulation.pose(of: .saqa).map { PoseClassifier.side(of: $0.rotation, shape: .saqa) }
        onEvent?(.settled(judgeFacts(), saqaSide: saqaSide))
    }

    private func settleIiru() {
        var sides: [Player: Side] = [:]
        for player in iiruSpinning {
            guard let pose = simulation.pose(of: .iiru(player)) else { continue }
            sides[player] = PoseClassifier.side(of: pose.rotation, shape: .saqa)
        }
        haptics.impact(.boneOnCarpet, speed: 2)
        onEvent?(.iiruSettled(sides))
    }

    /// What the judge sees on the field now (docs/05-rules.md, §3).
    private func judgeFacts() -> ThrowFacts {
        var facts = ThrowFacts()
        if let landing = hits.firstLanding, let aim {
            facts.isSlide = Judge.isSlide(landing: landing, spot: aim.spot, target: aim.target, category: category)
        }
        facts.touched = hits.touched
        for index in 0..<simulation.keneiCount where simulation.isOnField(kenei: index) {
            guard let pose = simulation.pose(of: .kenei(index)) else { continue }
            if Judge.isKnockedOut(position: pose.position, rotation: pose.rotation, shape: .kenei, circleRadius: category.circleRadius) {
                facts.knockedOut.append(index)
            } else if !isOnSlot(pose, index) {
                facts.displaced[index] = Judge.zone(of: pose.position, category: category)
            }
        }
        return facts
    }

    private func isOnSlot(_ pose: ArenaSimulation.Pose, _ index: Int) -> Bool {
        let slot = simulation.slot(index)
        let moved = simd_distance(pose.position, slot.position)
        let turned = abs(simd_dot(pose.rotation.vector, slot.rotation.vector))
        return moved < GameTuning.Field.slotTolerance && turned > 0.9995
    }

    // MARK: - Camera

    private func aimCamera(snap: Bool) {
        guard let aim else { return }
        let shot = CameraShot.aim(spot: aim.spot, target: aim.target, rowWidth: aim.framingWidth, aspect: camera.aspect)
        camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: shot.fieldOfView, spring: GameTuning.Camera.aimSpring)
        if snap { camera.snap() }
    }

    /// Frames the kon and everything that moved: kenei on their way out, the saqa if it's near.
    /// Anything far beyond the circle is clearly out; it's framed as if just past the line, so
    /// one wild kenei can't pull the camera to the far end of the hall.
    private func placeOverviewCamera() {
        guard let aim else { return }
        let direction = SimMath.normalize(SIMD3(aim.target.x - aim.spot.x, 0, aim.target.z - aim.spot.z))
        let limit = category.circleRadius + 0.5
        func clamped(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let flat = SIMD2(point.x, point.z)
            let distance = simd_length(flat)
            guard distance > limit else { return point }
            let pulled = flat / distance * limit
            return SIMD3(pulled.x, point.y, pulled.y)
        }
        var points: [SIMD3<Float>] = [.zero, aim.target]
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
        switch shot {
        case .aim:
            break
        case .flight(let direction):
            guard let aim else { break }
            let saqa = simulation.renderPose(of: .saqa)
            let passedTarget = saqa.map { SimMath.dot($0.position - aim.target, direction) > 0.4 } ?? false
            if reduceMotion {
                // No flying camera: hold the aim, then cut to the result.
                if hits.hitKon || passedTarget {
                    placeOverviewCamera()
                    camera.snap()
                }
            } else if let impact = hits.impactPoint, simulation.timeSinceThrow - hits.impactTime < GameTuning.Camera.impactHold {
                let shot = CameraShot.impact(point: impact, direction: direction, orbitSign: impact.x >= aim.spot.x ? 1 : -1)
                camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: GameTuning.Camera.chaseFieldOfView * 1.15, spring: GameTuning.Camera.impactSpring)
            } else if hits.hitKon || passedTarget {
                // The hit is over: rise while things still roll, to watch kenei cross the line.
                placeOverviewCamera()
            } else if let saqa {
                let shot = CameraShot.chase(saqa: saqa.position, direction: direction, target: aim.target)
                camera.aim(eye: shot.eye, focus: shot.focus, fieldOfView: GameTuning.Camera.chaseFieldOfView, spring: GameTuning.Camera.chaseSpring)
            }
        case .result:
            placeOverviewCamera()
        case .iiru:
            // Follow the spinning saqas, then settle between them.
            let poses = Player.allCases.compactMap { simulation.renderPose(of: .iiru($0))?.position }
            if !poses.isEmpty {
                var middle = poses.reduce(SIMD3<Float>.zero, +) / Float(poses.count)
                middle.y = 0
                iiruFocus.target = middle
            }
            iiruFocus.step(dt, SpringParameters(response: 0.6, dampingRatio: 1))
            placeIiruCamera()
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
        aimVisibility.target = gesture == nil || aim?.showsGuide == false ? 0 : 1
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

    /// A throw can start before a slow return ends; land them now.
    private func finishReturns() {
        for item in returns { simulation.place(kenei: item.index, at: item.to) }
        returns.removeAll()
    }

    // MARK: - Scene

    private func saqaColor(_ player: Player) -> SIMD4<Float> {
        SIMD4((player == .home ? Palette.saqa : Palette.rivalSaqa).linear, 0.85)
    }

    private func makeScene() -> ArenaRenderer.Scene {
        let boneColor = SIMD4(Palette.bone.linear, 0.32)
        var kenei: [ArenaRenderer.BoneInstance] = []
        var contacts: [SIMD4<Float>] = []
        let returning = Dictionary(uniqueKeysWithValues: returns.map { ($0.index, $0) })
        let target = aim?.targetKenei

        for index in 0..<simulation.keneiCount where simulation.isOnField(kenei: index) {
            guard var pose = simulation.renderPose(of: .kenei(index)) else { continue }
            if let item = returning[index] {
                let t = Float(min(max(item.progress.value, 0), 1.05))
                pose.position = simd_mix(item.from.position, item.to.position, SIMD3(repeating: t))
                pose.position.y += sin(min(t, 1) * .pi) * 0.05
                pose.rotation = simd_slerp(item.from.rotation, item.to.rotation, min(t, 1))
            }
            let scale = Float(arrivals[index]?.value ?? 1)
            // The kenei a special throw aims at breathes a soft glow.
            let glow: Float = index == target ? 0.35 + 0.15 * sin(Float(clock) * 4) : 0
            kenei.append(.init(model: simd_float4x4(position: pose.position, rotation: pose.rotation, scale: scale), color: boneColor, params: [0, glow, 0, 0]))
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

        var saqa: [ArenaRenderer.BoneInstance] = []
        if let pose = simulation.renderPose(of: .saqa) {
            saqa.append(.init(model: simd_float4x4(position: pose.position, rotation: pose.rotation), color: saqaColor(saqaOwner), params: [1, 0, 0, 0]))
            contacts.append(SIMD4(pose.position, 0.026))
        }
        for player in Player.allCases {
            guard let pose = simulation.renderPose(of: .iiru(player)) else { continue }
            saqa.append(.init(model: simd_float4x4(position: pose.position, rotation: pose.rotation), color: saqaColor(player), params: [1, 0, 0, 0]))
            contacts.append(SIMD4(pose.position, 0.026))
        }

        var hand: [ArenaRenderer.BoneInstance] = []
        if handScale.value > 0.001 {
            hand.append(.init(model: handModel(), color: saqaColor(.home), params: [1, 0, 0, 0]))
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
        if let gesture, gesture.isLongEnough, let aim {
            let launch = ThrowLaunch(input: gesture.input, release: ThrowLaunch.releasePoint(spot: aim.spot, target: aim.target), spot: aim.spot, target: aim.target)
            if let landing = launch.trajectory(samples: GameTuning.Throw.previewSamples).last {
                field.aimFrom = SIMD2(aim.spot.x, aim.spot.z)
                field.aimTo = SIMD2(landing.x, landing.z)
            }
        }
        field.aimVisibility = Float(aimVisibility.value)
        field.landingRingRadius = 0.09

        let shadowFocus: SIMD3<Float>
        switch shot {
        case .iiru:
            shadowFocus = iiruFocus.value
        case .flight:
            let saqaPosition = simulation.renderPose(of: .saqa)?.position ?? .zero
            shadowFocus = simd_mix(saqaPosition, aim?.target ?? .zero, SIMD3(repeating: 0.5))
        case .aim, .result:
            shadowFocus = aim.map { simd_mix($0.spot, $0.target, SIMD3(repeating: 0.55)) } ?? .zero
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
        let spin = simd_quatf(angle: -flick * 2.4, axis: right)
        return simd_float4x4(position: position, rotation: spin * tilt * idle * heading, scale: Float(handScale.value))
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
}
