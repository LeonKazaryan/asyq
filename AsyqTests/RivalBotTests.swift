import simd
import Testing
@testable import Asyq

@MainActor
struct RivalBotTests {
    let spot = SIMD3<Float>(0, 0, 6)

    /// After the middle of the kon is knocked out, aiming at the center would fly through the gap.
    @Test func aimsAtAKeneiNotTheGap() {
        let simulation = ArenaSimulation(category: .eresek)
        let kenei = (0..<15).filter { !(5...9).contains($0) }.map { simulation.slot($0).position }
        var bot = RivalBot(name: "Test", seed: 3)
        for _ in 0..<20 {
            let input = bot.chooseThrow(spot: spot, target: .zero, kenei: kenei)
            // Where the throw's line crosses the kon.
            let lateral = -tan(input.angle) * 6
            let nearest = kenei.map { abs($0.x - lateral) }.min() ?? .infinity
            #expect(abs(lateral) > 0.12, "aimed into the gap")
            #expect(nearest < 0.2)
        }
    }

    @Test func aimsForTheTargetDistance() {
        var bot = RivalBot(name: "Test", seed: 9)
        let kenei: [SIMD3<Float>] = [[0, 0.01, 0]]
        let powers = (0..<50).map { _ in bot.chooseThrow(spot: spot, target: .zero, kenei: kenei).power }
        let mean = powers.reduce(0, +) / Float(powers.count)
        // A hair past half a pull.
        #expect(mean > 0.5 && mean < 0.58)
    }

    @Test func theSameSeedPlaysTheSame() {
        var first = RivalBot(name: "A", seed: 42)
        var second = RivalBot(name: "B", seed: 42)
        let kenei: [SIMD3<Float>] = [[0.1, 0.01, 0], [-0.2, 0.01, 0]]
        for _ in 0..<10 {
            #expect(first.chooseThrow(spot: spot, target: .zero, kenei: kenei) == second.chooseThrow(spot: spot, target: .zero, kenei: kenei))
        }
    }
}
