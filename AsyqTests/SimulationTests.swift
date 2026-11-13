import AsyqPhysics
import simd
import Testing
@testable import Asyq

@MainActor
struct SimulationTests {
    private func play(_ input: ThrowInput, category: AgeCategory = .eresek) -> (simulation: ArenaSimulation, hits: [ArenaSimulation.Hit]) {
        let simulation = ArenaSimulation(category: category)
        let spot = SIMD3<Float>(0, 0, category.throwDistance)
        let launch = ThrowLaunch(input: input, release: ThrowLaunch.releasePoint(spot: spot, target: .zero), spot: spot, target: .zero)
        simulation.throwSaqa(launch)
        let hits = simulation.runUntilSettled()
        return (simulation, hits)
    }

    private func poses(_ simulation: ArenaSimulation) -> [ArenaSimulation.Pose?] {
        (0..<simulation.keneiCount).map { simulation.pose(of: .kenei($0)) } + [simulation.pose(of: .saqa)]
    }

    @Test func theKonStandsStillUntilHit() {
        let simulation = ArenaSimulation(category: .eresek)
        for index in 0..<simulation.keneiCount {
            let pose = simulation.pose(of: .kenei(index))
            #expect(pose == simulation.slot(index))
            #expect(PoseClassifier.side(of: simulation.slot(index).rotation, shape: .kenei) == .alshy)
        }
    }

    @Test func theKonFitsOnItsLine() {
        let simulation = ArenaSimulation(category: .eresek)
        let first = simulation.slot(0).position.x - BoneShape.kenei.halfExtents.x
        let last = simulation.slot(simulation.keneiCount - 1).position.x + BoneShape.kenei.halfExtents.x
        #expect(last - first <= AgeCategory.eresek.konLength)
    }

    /// docs/03-architecture.md, «Детерминизм»: the same throw ends the same way, to the bit.
    @Test func theSameThrowEndsTheSameWay() {
        let input = ThrowInput(angle: 0.02, power: 0.63, spin: 0.3)
        let first = play(input)
        let second = play(input)
        #expect(poses(first.simulation) == poses(second.simulation))
        #expect(first.hits.count == second.hits.count)
    }

    @Test func aThrowAlwaysComesToRest() {
        for power in stride(from: Float(0.1), through: 1, by: 0.3) {
            let result = play(ThrowInput(angle: 0, power: power, spin: 1))
            #expect(!result.simulation.isThrowInProgress)
            #expect(result.simulation.timeSinceThrow <= GameTuning.Simulation.maxSettleTime + 0.01)
        }
    }

    @Test func aGoodThrowHitsTheKonAndCanKnockKeneiOut() {
        // Somewhere in a sweep of sensible throws the saqa must reach the kon, and some must
        // send a kenei out of the circle: the game is playable.
        var hitKon = 0
        var knockedOut = 0
        // Half a pull lands on the kon (`ThrowInput.range`); sweep around it.
        for step in 0..<21 {
            let power = 0.46 + Float(step) * 0.01
            let result = play(ThrowInput(angle: Float(step % 3 - 1) * 0.01, power: power))
            if result.hits.contains(where: \.isSaqaOnKenei) { hitKon += 1 }
            for index in 0..<result.simulation.keneiCount {
                guard let pose = result.simulation.pose(of: .kenei(index)) else { continue }
                if Judge.isKnockedOut(position: pose.position, rotation: pose.rotation, shape: .kenei, circleRadius: AgeCategory.eresek.circleRadius) {
                    knockedOut += 1
                }
            }
        }
        #expect(hitKon > 0)
        #expect(knockedOut > 0)
    }

    /// Iiru on the placeholder bone: wide sides must win, narrow ones must be rarer, ends rarest.
    /// Real calibration (≈40/40/10/10) waits for the scans (M3, ADR-003).
    @Test func sidesFallWithBoneLikeOdds() {
        let world = PhysicsWorld()
        world.setSurfacePair(GameTuning.Surface.bone, GameTuning.Surface.carpet, SurfacePair(friction: GameTuning.Surface.boneOnCarpet.friction, restitution: GameTuning.Surface.boneOnCarpet.restitution))
        world.addStaticBox(halfExtents: [10, 0.5, 10], position: [0, -0.5, 0], material: GameTuning.Surface.carpet)
        let shape = world.makeRoundedBoxShape(halfExtents: BoneShape.kenei.halfExtents, cornerRadius: BoneShape.kenei.cornerRadius)
        var counts: [Side: Int] = [:]
        var generator = SeededRandom(seed: 2026)
        let throwCount = 600
        for _ in 0..<throwCount {
            let axis = SIMD3<Float>(generator.unit(), generator.unit(), generator.unit())
            let id = world.addBody(shape: shape, description: BodyDescription(
                mass: BoneShape.kenei.mass,
                material: GameTuning.Surface.bone,
                position: [0, 0.25, 0],
                rotation: SimMath.rotation(angle: generator.unit() * 3.1, axis: axis),
                continuousCollision: true
            ))
            world.setVelocity(id, linear: [generator.unit() * 0.5, -1, generator.unit() * 0.5], angular: SIMD3(generator.unit(), generator.unit(), generator.unit()) * 30)
            var time: Float = 0
            while world.isAwake(id), time < 6 {
                world.step(deltaTime: 1 / 240)
                time += 1 / 240
            }
            counts[PoseClassifier.side(of: world.rotation(of: id), shape: .kenei), default: 0] += 1
            world.removeBody(id)
        }
        let wide = (counts[.buk] ?? 0) + (counts[.shik] ?? 0)
        let narrow = (counts[.alshy] ?? 0) + (counts[.taike] ?? 0)
        let ends = (counts[.ompy] ?? 0) + (counts[.shonqai] ?? 0)
        print("Iiru on the placeholder (\(throwCount)):", Side.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", "))
        #expect(wide > narrow)
        #expect(narrow > ends)
        #expect(Double(wide) / Double(throwCount) > 0.45)
    }
}
