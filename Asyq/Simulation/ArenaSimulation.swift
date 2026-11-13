import AsyqPhysics
import simd

/// The kon, the saqa and the carpet as a Jolt world. Physics always advances in fixed
/// 1/240 s steps from the moment of a throw, so a throw's outcome depends only on the table and
/// the `ThrowInput` — never on frame timing or slow motion (docs/03-architecture.md).
/// Rendering reads transforms interpolated between the last two steps.
@MainActor
final class ArenaSimulation {
    enum Piece: Hashable, Sendable {
        case kenei(Int)
        case saqa
        /// A player's saqa spun to decide who starts (иіру), away from the kon.
        case iiru(Player)
        case carpet
    }

    struct Pose: Equatable, Sendable {
        var position: SIMD3<Float>
        var rotation: simd_quatf
    }

    /// Two things touched. `speed` is how fast they closed, m/s.
    struct Hit: Sendable {
        var first: Piece
        var second: Piece
        var point: SIMD3<Float>
        var speed: Float

        func involves(_ piece: Piece) -> Bool {
            first == piece || second == piece
        }

        var isSaqaOnKenei: Bool {
            switch (first, second) {
            case (.saqa, .kenei), (.kenei, .saqa): true
            default: false
            }
        }

        var isOnCarpet: Bool {
            first == .carpet || second == .carpet
        }
    }

    let category: AgeCategory
    static let stepTime = 1 / GameTuning.Simulation.stepRate

    private let world: PhysicsWorld
    private let keneiShape: PhysicsShape
    private let saqaShape: PhysicsShape
    private let carpetID: BodyID
    private var keneiIDs: [BodyID?] = []
    private var saqaID: BodyID?
    private var iiruIDs: [Player: BodyID] = [:]
    private var pieces: [BodyID: Piece] = [:]
    private var previous: [Piece: Pose] = [:]
    private var current: [Piece: Pose] = [:]
    private var accumulator: Float = 0
    /// Simulated time since the last throw.
    private(set) var timeSinceThrow: Float = 0
    private(set) var isThrowInProgress = false

    init(category: AgeCategory) {
        self.category = category
        world = PhysicsWorld()
        let surface = GameTuning.Surface.self
        world.setSurfacePair(surface.bone, surface.bone, SurfacePair(friction: surface.boneOnBone.friction, restitution: surface.boneOnBone.restitution))
        world.setSurfacePair(surface.bone, surface.carpet, SurfacePair(friction: surface.boneOnCarpet.friction, restitution: surface.boneOnCarpet.restitution))
        keneiShape = world.makeRoundedBoxShape(halfExtents: BoneShape.kenei.halfExtents, cornerRadius: BoneShape.kenei.cornerRadius)
        saqaShape = world.makeRoundedBoxShape(halfExtents: BoneShape.saqa.halfExtents, cornerRadius: BoneShape.saqa.cornerRadius)
        // A slab of carpet much bigger than the field, its top at y = 0.
        carpetID = world.addStaticBox(halfExtents: [40, 0.5, 40], position: [0, -0.5, 0], material: surface.carpet)
        pieces[carpetID] = .carpet
        resetKon()
    }

    // MARK: - The table

    /// Where kenei `index` stands on the kon: in a row along x, alshy up, one saqa apart
    /// (Регламент, с. 62).
    func slot(_ index: Int) -> Pose {
        let count = category.keneiCount
        let spacing = GameTuning.Field.keneiSpacing
        let x = (Float(index) - Float(count - 1) / 2) * spacing
        let rotation = BoneShape.kenei.restingRotation(.alshy)
        let y = BoneShape.kenei.restingHeight(rotation: rotation) + GameTuning.Field.restingClearance
        return Pose(position: [x, y, 0], rotation: rotation)
    }

    var keneiCount: Int { keneiIDs.count }

    func isOnField(kenei index: Int) -> Bool {
        keneiIDs.indices.contains(index) && keneiIDs[index] != nil
    }

    /// A fresh kon: every kenei back on its slot, no saqa.
    func resetKon() {
        for case let id? in keneiIDs { remove(id) }
        if let saqaID { remove(saqaID) }
        saqaID = nil
        keneiIDs = (0..<category.keneiCount).map { index in
            let pose = slot(index)
            let id = world.addBody(shape: keneiShape, description: BodyDescription(
                mass: BoneShape.kenei.mass,
                material: GameTuning.Surface.bone,
                position: pose.position,
                rotation: pose.rotation,
                linearDamping: GameTuning.Bone.linearDamping,
                angularDamping: GameTuning.Bone.angularDamping,
                continuousCollision: true,
                startsAsleep: true
            ))
            pieces[id] = .kenei(index)
            current[.kenei(index)] = pose
            previous[.kenei(index)] = pose
            return id
        }
        isThrowInProgress = false
    }

    func removeKenei(_ index: Int) {
        guard isOnField(kenei: index), let id = keneiIDs[index] else { return }
        remove(id)
        keneiIDs[index] = nil
        current[.kenei(index)] = nil
        previous[.kenei(index)] = nil
    }

    func removeSaqa() {
        guard let saqaID else { return }
        remove(saqaID)
        self.saqaID = nil
        current[.saqa] = nil
        previous[.saqa] = nil
    }

    /// Takes the iiru saqas off the carpet.
    func removeIiru() {
        for player in Player.allCases {
            guard let id = iiruIDs[player] else { continue }
            remove(id)
            current[.iiru(player)] = nil
            previous[.iiru(player)] = nil
        }
        iiruIDs = [:]
    }

    /// Puts a kenei somewhere (after a miss: back on its slot), asleep.
    func place(kenei index: Int, at pose: Pose) {
        guard isOnField(kenei: index), let id = keneiIDs[index] else { return }
        world.setTransform(id, position: pose.position, rotation: pose.rotation, activate: false)
        world.setVelocity(id, linear: .zero, angular: .zero)
        world.putToSleep(id)
        current[.kenei(index)] = pose
        previous[.kenei(index)] = pose
    }

    private func remove(_ id: BodyID) {
        world.removeBody(id)
        pieces[id] = nil
    }

    // MARK: - Throwing

    func throwSaqa(_ launch: ThrowLaunch) {
        removeSaqa()
        let id = addSaqa(at: launch.position, rotation: launch.rotation)
        world.setVelocity(id, linear: launch.linearVelocity, angular: launch.angularVelocity)
        saqaID = id
        pieces[id] = .saqa
        start(.saqa, at: launch.position, rotation: launch.rotation)
    }

    /// Drops a player's saqa spinning onto the carpet: иіру. Several can be in the air at once.
    func spin(_ player: Player, _ drop: IiruDrop) {
        if let old = iiruIDs[player] { remove(old) }
        let id = addSaqa(at: drop.position, rotation: drop.rotation)
        world.setVelocity(id, linear: drop.linearVelocity, angular: drop.angularVelocity)
        iiruIDs[player] = id
        pieces[id] = .iiru(player)
        start(.iiru(player), at: drop.position, rotation: drop.rotation)
    }

    private func addSaqa(at position: SIMD3<Float>, rotation: simd_quatf) -> BodyID {
        world.addBody(shape: saqaShape, description: BodyDescription(
            mass: BoneShape.saqa.mass,
            material: GameTuning.Surface.bone,
            position: position,
            rotation: rotation,
            linearDamping: GameTuning.Bone.linearDamping,
            angularDamping: GameTuning.Bone.angularDamping,
            continuousCollision: true
        ))
    }

    private func start(_ piece: Piece, at position: SIMD3<Float>, rotation: simd_quatf) {
        let pose = Pose(position: position, rotation: rotation)
        current[piece] = pose
        previous[piece] = pose
        _ = world.drainContactEvents()
        // Motion starts on a step boundary: the same input always replays the same way.
        accumulator = 0
        timeSinceThrow = 0
        isThrowInProgress = true
    }

    /// Advances by `realTime` seconds of clock time, slowed by `timeScale`. Returns the hits.
    func advance(realTime: Double, timeScale: Float) -> [Hit] {
        guard isThrowInProgress else { return [] }
        accumulator += Float(realTime) * timeScale
        var steps = 0
        var hits: [Hit] = []
        while accumulator >= Self.stepTime, steps < GameTuning.Simulation.maxStepsPerFrame, isThrowInProgress {
            hits += step()
            accumulator -= Self.stepTime
            steps += 1
        }
        // Behind by more than a frame's budget: drop the backlog rather than spiral.
        if steps == GameTuning.Simulation.maxStepsPerFrame {
            accumulator = min(accumulator, Self.stepTime)
        }
        return hits
    }

    /// Runs the throw to rest without a clock: for tests and, later, the bot.
    func runUntilSettled() -> [Hit] {
        var hits: [Hit] = []
        while isThrowInProgress {
            hits += step()
        }
        return hits
    }

    private func step() -> [Hit] {
        world.step(deltaTime: Self.stepTime)
        timeSinceThrow += Self.stepTime
        previous = current
        for (id, piece) in pieces where piece != .carpet {
            current[piece] = Pose(position: world.position(of: id), rotation: world.rotation(of: id))
        }
        let hits = world.drainContactEvents().compactMap { event -> Hit? in
            guard let first = pieces[event.bodyA], let second = pieces[event.bodyB] else { return nil }
            return Hit(first: first, second: second, point: event.point, speed: event.approachSpeed)
        }
        if !world.hasAwakeBodies {
            isThrowInProgress = false
        } else if timeSinceThrow >= GameTuning.Simulation.maxSettleTime {
            // The turn must end: whatever still crawls stops where it is. Sorted, so nothing
            // here depends on dictionary order.
            for id in pieces.keys.sorted(by: { $0.rawValue < $1.rawValue }) where id != carpetID {
                world.putToSleep(id)
            }
            isThrowInProgress = false
        }
        return hits
    }

    // MARK: - Reading

    /// The pose to draw: between the last two physics steps.
    func renderPose(of piece: Piece) -> Pose? {
        guard let now = current[piece] else { return nil }
        guard isThrowInProgress, let before = previous[piece] else { return now }
        let t = min(max(accumulator / Self.stepTime, 0), 1)
        return Pose(
            position: simd_mix(before.position, now.position, SIMD3(repeating: t)),
            rotation: simd_slerp(before.rotation, now.rotation, t)
        )
    }

    /// The pose at the last physics step.
    func pose(of piece: Piece) -> Pose? {
        current[piece]
    }
}
