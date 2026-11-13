import AsyqPhysics
import simd
import Testing

private enum Material {
    static let bone: UInt8 = 0
    static let carpet: UInt8 = 1
}

private let step: Float = 1.0 / 240
/// About a kenei: 3 cm long, 2.2 cm wide, 1.6 cm thick.
private let boneHalfExtents: SIMD3<Float> = [0.015, 0.008, 0.011]
private let boneCorner: Float = 0.004
private let boneMass: Float = 0.016

private func makeWorld(config: PhysicsWorldConfig = .init(), carpet: SurfacePair = .init(friction: 0.7, restitution: 0.15)) -> PhysicsWorld {
    let world = PhysicsWorld(config: config)
    world.setSurfacePair(Material.bone, Material.carpet, carpet)
    world.setSurfacePair(Material.bone, Material.bone, SurfacePair(friction: 0.3, restitution: 0.6))
    // Top face at y = 0.
    world.addStaticBox(halfExtents: [5, 0.05, 5], position: [0, -0.05, 0], material: Material.carpet)
    return world
}

private func addBone(to world: PhysicsWorld, at position: SIMD3<Float>, rotation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1), fast: Bool = false) -> BodyID {
    let shape = world.makeRoundedBoxShape(halfExtents: boneHalfExtents, cornerRadius: boneCorner)
    return world.addBody(shape: shape, description: BodyDescription(mass: boneMass, material: Material.bone, position: position, rotation: rotation, continuousCollision: fast))
}

/// Steps until everything sleeps or `seconds` run out; returns the simulated time.
@discardableResult
private func settle(_ world: PhysicsWorld, seconds: Float = 3) -> Float {
    var time: Float = 0
    while time < seconds {
        world.step(deltaTime: step)
        time += step
        if !world.hasAwakeBodies { break }
    }
    return time
}

private func randomRotation(using random: inout SplitMix64) -> simd_quatf {
    let axis = SIMD3<Float>(Float.random(in: -1...1, using: &random), Float.random(in: -1...1, using: &random), Float.random(in: -1...1, using: &random) + 0.001)
    return DeterministicMath.rotation(angle: Float.random(in: 0...(2 * .pi), using: &random), axis: axis)
}

/// Deterministic random numbers, so the throws in a test are the same every run.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// FNV-1a over the exact bits, so any difference in rounding shows.
private func fingerprint(_ positions: [SIMD3<Float>], _ rotations: [simd_quatf]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    let floats = positions.flatMap { [$0.x, $0.y, $0.z] } + rotations.flatMap { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] }
    for value in floats {
        hash = (hash ^ UInt64(value.bitPattern)) &* 0x0000_0100_0000_01B3
    }
    return hash
}

struct PhysicsWorldTests {
    static let expectedFingerprint: UInt64 = 16_407_162_623_641_466_248
    @Test func droppedBoneComesToRestAndSleeps() {
        let world = makeWorld()
        let bone = addBone(to: world, at: [0, 0.3, 0])
        var highestAfterImpact: Float = 0
        var landed = false
        var time: Float = 0
        while time < 3 {
            world.step(deltaTime: step)
            time += step
            let y = world.position(of: bone).y
            #expect(y.isFinite)
            if y < 0.02 { landed = true }
            if landed { highestAfterImpact = max(highestAfterImpact, y) }
            if !world.hasAwakeBodies { break }
        }
        #expect(!world.isAwake(bone), "still awake after \(time) s")
        #expect(time < 3)
        // Dropped flat, it lies on a wide face: its center is half the thickness up.
        #expect(abs(world.position(of: bone).y - boneHalfExtents.y) < 0.001)
        // A small hop on the carpet, nothing like the drop height: no explosion.
        #expect(highestAfterImpact < 0.05)
    }

    @Test func sameThrowGivesBitIdenticalResults() {
        func run() -> ([SIMD3<Float>], [simd_quatf], [ContactEvent], Set<BodyID>) {
            let world = makeWorld()
            // A row of kenei and a saqa thrown into them: lots of bone-on-bone contacts.
            var bones = (0..<5).map { index in
                addBone(to: world, at: [Float(index) * 0.035 - 0.07, boneHalfExtents.z, 0.6], rotation: DeterministicMath.rotation(angle: .pi / 2, axis: [1, 0, 0]))
            }
            let saqa = addBone(to: world, at: [0.01, 0.015, 0.45], fast: true)
            world.setVelocity(saqa, linear: [-0.05, 0.2, 3], angular: [12, -4, 7])
            bones.append(saqa)
            var events: [ContactEvent] = []
            for _ in 0..<1200 {
                world.step(deltaTime: step)
                events += world.drainContactEvents()
            }
            return (bones.map { world.position(of: $0) }, bones.map { world.rotation(of: $0) }, events, Set(bones))
        }
        let first = run()
        let second = run()
        print("[AsyqPhysics fingerprint] \(fingerprint(first.0, first.1))")
        // Recorded on macOS; the same number on the iOS simulator and devices proves the
        // simulation is identical across platforms. Changes only with a Jolt update or a
        // deliberate change to this scenario: then re-record it.
        #expect(fingerprint(first.0, first.1) == Self.expectedFingerprint)
        #expect(first.0 == second.0)
        #expect(first.1.map(\.vector) == second.1.map(\.vector))
        #expect(first.2.count == second.2.count)
        #expect(zip(first.2, second.2).allSatisfy { $0.bodyA == $1.bodyA && $0.bodyB == $1.bodyB && $0.point == $1.point && $0.approachSpeed == $1.approachSpeed })
        // The saqa did hit the row, or this test proves little.
        #expect(first.2.contains { first.3.contains($0.bodyA) && first.3.contains($0.bodyB) && $0.approachSpeed > 0.5 })
    }

    @Test func continuousCollisionStopsTunnelingThroughAThinWall() {
        var config = PhysicsWorldConfig()
        config.gravity = .zero
        let world = PhysicsWorld(config: config)
        world.setSurfacePair(Material.bone, Material.carpet, SurfacePair(friction: 0.5, restitution: 0.2))
        // 2 cm thick, its near face at x = 0.49.
        world.addStaticBox(halfExtents: [0.01, 0.2, 0.5], position: [0.5, 0, 0], material: Material.carpet)
        let bone = addBone(to: world, at: [0, 0, 0], fast: true)
        world.setVelocity(bone, linear: [15, 0, 0], angular: .zero)
        for _ in 0..<48 { world.step(deltaTime: step) }
        #expect(world.position(of: bone).x < 0.49)
    }

    @Test func dropReportsImpactWithTheGround() throws {
        let world = makeWorld()
        let bone = addBone(to: world, at: [0, 0.2, 0])
        var first: ContactEvent?
        for _ in 0..<240 where first == nil {
            world.step(deltaTime: step)
            first = world.drainContactEvents().first
        }
        let event = try #require(first)
        #expect(event.bodyA == bone)
        // Free fall from 0.2 m with the bone's bottom 8 mm lower: √(2 g h) ≈ 1.94 m/s.
        let expected = (2 * 9.81 * (0.2 - boneHalfExtents.y)).squareRoot()
        #expect(abs(event.approachSpeed - expected) / expected < 0.1, "approach \(event.approachSpeed), expected \(expected)")
        // From the bone towards the ground.
        #expect(event.normal.y < -0.9)
        #expect(abs(event.point.y) < 0.005)
    }

    @Test func twoBonesHittingReportEachOther() throws {
        var config = PhysicsWorldConfig()
        config.gravity = .zero
        let world = PhysicsWorld(config: config)
        world.setSurfacePair(Material.bone, Material.bone, SurfacePair(friction: 0.3, restitution: 0.6))
        let left = addBone(to: world, at: [-0.1, 0, 0])
        let right = addBone(to: world, at: [0.1, 0, 0])
        world.setVelocity(left, linear: [1, 0, 0], angular: .zero)
        world.setVelocity(right, linear: [-1, 0, 0], angular: .zero)
        var events: [ContactEvent] = []
        for _ in 0..<120 {
            world.step(deltaTime: step)
            events += world.drainContactEvents()
        }
        let hit = try #require(events.first)
        #expect(Set([hit.bodyA, hit.bodyB]) == Set([left, right]))
        #expect(abs(hit.approachSpeed - 2) < 0.2)
    }

    @Test func bouncierSurfaceBouncesHigher() {
        func bounceHeight(restitution: Float) -> Float {
            let world = makeWorld(carpet: SurfacePair(friction: 0.7, restitution: restitution))
            let bone = addBone(to: world, at: [0, 0.3, 0])
            var landed = false
            var highest: Float = 0
            for _ in 0..<480 {
                world.step(deltaTime: step)
                if !world.drainContactEvents().isEmpty { landed = true }
                if landed { highest = max(highest, world.position(of: bone).y) }
            }
            return highest
        }
        let lively = bounceHeight(restitution: 0.8)
        let dead = bounceHeight(restitution: 0.1)
        #expect(lively > dead + 0.05, "lively \(lively), dead \(dead)")
    }

    @Test func convexHullBoneRestsStably() throws {
        let world = makeWorld()
        // A box-ish hull with a ridge on top, like the back of a bone.
        let h = boneHalfExtents
        var points: [SIMD3<Float>] = []
        for x in [-h.x, h.x] { for y in [-h.y, h.y * 0.7] { for z in [-h.z, h.z] { points.append([x, y, z]) } } }
        points += [[-h.x * 0.6, h.y, 0], [h.x * 0.6, h.y, 0]]
        let shape = try #require(world.makeConvexHullShape(points: points, convexRadius: 0.002))
        let bone = world.addBody(shape: shape, description: BodyDescription(mass: boneMass, material: Material.bone, position: [0, 0.1, 0]))
        let time = settle(world)
        #expect(time < 3)
        #expect(!world.isAwake(bone))
        #expect(abs(world.position(of: bone).y - h.y) < 0.002)
        #expect(world.makeConvexHullShape(points: [[0, 0, 0], [1, 0, 0]], convexRadius: 0.001) == nil)
    }

    @Test func restoringASnapshotReplaysTheSameFuture() {
        let world = makeWorld()
        let row = (0..<3).map { index in addBone(to: world, at: [Float(index) * 0.035 - 0.035, boneHalfExtents.y, 0.5]) }
        let saqa = addBone(to: world, at: [0, 0.1, 0], fast: true)
        world.setVelocity(saqa, linear: [0, 1, 4], angular: [5, 0, 0])
        for _ in 0..<30 { world.step(deltaTime: step) }
        let snapshot = world.snapshot()
        #expect(!snapshot.bytes.isEmpty)

        func future() -> [SIMD3<Float>] {
            for _ in 0..<600 { world.step(deltaTime: step) }
            return (row + [saqa]).map { world.position(of: $0) }
        }
        let first = future()
        #expect(world.restore(snapshot))
        let second = future()
        #expect(first == second)
    }

    @Test func removedBodyLeavesTheWorld() {
        let world = makeWorld()
        let bone = addBone(to: world, at: [0, 0.1, 0])
        #expect(world.bodyCount == 2)
        world.removeBody(bone)
        #expect(world.bodyCount == 1)
        #expect(!world.hasAwakeBodies)
    }

    /// Sizes the 10 000-throw side frequency test in the app. Prints, doesn't assert speed.
    @Test func thousandSpunDropsPerformance() {
        let world = makeWorld()
        let shape = world.makeRoundedBoxShape(halfExtents: boneHalfExtents, cornerRadius: boneCorner)
        var random = SplitMix64(state: 42)
        var steps = 0
        var restingAxis: [String: Int] = [:]
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<1000 {
                let rotation = randomRotation(using: &random)
                let bone = world.addBody(shape: shape, description: BodyDescription(mass: boneMass, material: Material.bone, position: [0, 0.12, 0], rotation: rotation))
                world.setVelocity(bone, linear: [Float.random(in: -0.3...0.3, using: &random), 0, Float.random(in: -0.3...0.3, using: &random)], angular: [Float.random(in: -30...30, using: &random), Float.random(in: -30...30, using: &random), Float.random(in: -30...30, using: &random)])
                var time: Float = 0
                while time < 3 {
                    world.step(deltaTime: step)
                    steps += 1
                    time += step
                    if !world.isAwake(bone) { break }
                }
                _ = world.drainContactEvents()
                // Which body axis points down: ±x the ends, ±y the wide faces, ±z the narrow sides.
                let down = world.rotation(of: bone).inverse.act([0, -1, 0])
                let magnitudes = abs(down)
                let key = magnitudes.x > max(magnitudes.y, magnitudes.z) ? "end" : (magnitudes.y > magnitudes.z ? "wide" : "narrow")
                restingAxis[key, default: 0] += 1
                world.removeBody(bone)
            }
        }
        print("[AsyqPhysics perf] 1000 spun drops: \(elapsed), \(steps) steps, \(elapsed / steps) per step; rests: \(restingAxis.sorted { $0.key < $1.key })")
        #expect(restingAxis.values.reduce(0, +) == 1000)
    }
}

struct DeterministicMathTests {
    @Test func sinCosMatchesLibmClosely() {
        for angle in stride(from: Float(-6), through: 6, by: 0.37) {
            let (sine, cosine) = DeterministicMath.sinCos(angle)
            #expect(abs(sine - sin(angle)) < 1e-6)
            #expect(abs(cosine - cos(angle)) < 1e-6)
        }
    }

    @Test func rotationTurnsAroundTheAxis() {
        let quarter = DeterministicMath.rotation(angle: .pi / 2, axis: [0, 2, 0])
        let turned = quarter.act([1, 0, 0])
        #expect(simd_distance(turned, [0, 0, -1]) < 1e-5)
        #expect(abs(simd_length(quarter.vector) - 1) < 1e-6)
    }
}
