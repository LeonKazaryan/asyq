import Foundation
import simd
import Testing
@testable import Asyq

/// Where each throw comes from (docs/05-rules.md, §3; the Регламент's diagrams, с. 24–25).
struct ThrowSpotGeometryTests {
    private let category = AgeCategory.eresek
    private var radius: Float { category.circleRadius }

    private func place(_ spot: ThrowSpot, _ thrower: Player = .home, kenei: SIMD3<Float>? = nil) -> (spot: SIMD3<Float>, target: SIMD3<Float>) {
        ThrowSpotGeometry.place(spot, thrower: thrower, category: category, kenei: kenei)
    }

    private func expectPlaced(_ placed: (spot: SIMD3<Float>, target: SIMD3<Float>), at spot: SIMD3<Float>, aiming target: SIMD3<Float>, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(placed.spot == spot, sourceLocation: sourceLocation)
        #expect(placed.target == target, sourceLocation: sourceLocation)
    }

    private func flatLength(_ v: SIMD3<Float>) -> Float {
        (v.x * v.x + v.z * v.z).squareRoot()
    }

    @Test func eachPlayerThrowsFromTheirOwnLineAtTheKon() {
        expectPlaced(place(.line, .home), at: [0, 0, 6], aiming: .zero)
        expectPlaced(place(.line, .away), at: [0, 0, -6], aiming: .zero)
        let bala = ThrowSpotGeometry.place(.line, thrower: .home, category: .bala, kenei: nil)
        #expect(bala.spot == SIMD3(0, 0, 3))
    }

    @Test func aSeriesComesFromTheEdgeOnTheThrowersSide() {
        expectPlaced(place(.circleEdge, .home), at: [0, 0, 2.5], aiming: .zero)
        expectPlaced(place(.circleEdge, .away), at: [0, 0, -2.5], aiming: .zero)
    }

    @Test func besTabanIsFiveTabansOfArcAlongTheCircle() {
        let kenei = SIMD3<Float>(1.4, 0.01, -1.8)
        for flank in [Flank.left, .right] {
            let placed = place(.besTaban(kenei: 0, flank: flank), kenei: kenei)
            #expect(placed.target == kenei)
            #expect(placed.spot.y == 0)
            #expect(abs(flatLength(placed.spot) - radius) < 1e-5)
            // The arc between the kenei's bearing and the spot.
            let bearing = SIMD2(kenei.x, kenei.z) / flatLength(kenei)
            let spot = SIMD2(placed.spot.x, placed.spot.z) / radius
            let angle = acos(min(max(simd_dot(bearing, spot), -1), 1))
            #expect(abs(angle * radius - 5 * GameTuning.Rules.taban) < 1e-3)
        }
    }

    @Test func leftTurnsCounterclockwiseSeenFromAbove() {
        // A kenei by the line on the +x side: counterclockwise from above takes +x toward −z,
        // the away half; clockwise toward +z, the home half.
        let kenei = SIMD3<Float>(2.35, 0, 0)
        #expect(place(.besTaban(kenei: 0, flank: .left), kenei: kenei).spot.z < 0)
        #expect(place(.besTaban(kenei: 0, flank: .right), kenei: kenei).spot.z > 0)
        // On the home side (+z), counterclockwise goes toward +x.
        let nearHome = SIMD3<Float>(0, 0, 2.35)
        #expect(place(.besTaban(kenei: 0, flank: .left), kenei: nearHome).spot.x > 0)
        #expect(place(.besTaban(kenei: 0, flank: .right), kenei: nearHome).spot.x < 0)
    }

    @Test func diagonalComesFromTheFarSideThroughTheKon() {
        let kenei = SIMD3<Float>(0.6, 0.01, -1.2)
        let placed = place(.diagonal(kenei: 0), kenei: kenei)
        #expect(placed.target == kenei)
        #expect(abs(flatLength(placed.spot) - radius) < 1e-5)
        // Opposite the kenei: the line from the spot to it passes through the center.
        let toKenei = SIMD2(kenei.x - placed.spot.x, kenei.z - placed.spot.z)
        let toCenter = SIMD2(-placed.spot.x, -placed.spot.z)
        let cross = toKenei.x * toCenter.y - toKenei.y * toCenter.x
        #expect(abs(cross) < 1e-4)
        #expect(simd_dot(toKenei, toCenter) > 0)
        #expect(placed.spot.z > 0 && placed.spot.x < 0)
    }

    @Test func parallelComesFromAWingOnTheKonAxis() {
        let kenei = SIMD3<Float>(0.2, 0.01, 0.08)
        expectPlaced(place(.parallel(kenei: 0, flank: .left), kenei: kenei), at: [-2.5, 0, 0], aiming: kenei)
        expectPlaced(place(.parallel(kenei: 0, flank: .right), kenei: kenei), at: [2.5, 0, 0], aiming: kenei)
    }

    @Test func specialThrowsWithoutAKeneiFallBackToTheEdge() {
        #expect(place(.diagonal(kenei: 0), .away).spot == SIMD3(0, 0, -2.5))
        #expect(place(.besTaban(kenei: 0, flank: .left)).spot == SIMD3(0, 0, 2.5))
        #expect(place(.parallel(kenei: 0, flank: .left)).spot == SIMD3(0, 0, 2.5))
        // A kenei dead in the middle has no bearing.
        #expect(place(.diagonal(kenei: 0), kenei: SIMD3(0, 0.01, 0)).spot == SIMD3(0, 0, 2.5))
    }

    @Test func parallelDefaultsToTheNearerWing() {
        let left = SIMD3<Float>(-0.3, 0, 0.05)
        let right = SIMD3<Float>(0.3, 0, 0.05)
        #expect(ThrowSpotGeometry.nearestFlank(for: .parallel(kenei: 0, flank: .right), thrower: .home, category: category, kenei: left) == .left)
        #expect(ThrowSpotGeometry.nearestFlank(for: .parallel(kenei: 0, flank: .left), thrower: .home, category: category, kenei: right) == .right)
        // Dead center: a tie goes right.
        #expect(ThrowSpotGeometry.nearestFlank(for: .parallel(kenei: 0, flank: .left), thrower: .home, category: category, kenei: [0, 0, 0.05]) == .right)
    }

    @Test func besTabanDefaultsToTheThrowersOwnHalf() {
        // Both spots are equally far; the one on the thrower's half wins.
        let kenei = SIMD3<Float>(2.35, 0, 0)
        let spot = ThrowSpot.besTaban(kenei: 0, flank: .right)
        #expect(ThrowSpotGeometry.nearestFlank(for: spot, thrower: .home, category: category, kenei: kenei) == .right)
        #expect(ThrowSpotGeometry.nearestFlank(for: spot, thrower: .away, category: category, kenei: kenei) == .left)
        // On the axis both halves are the same: a tie goes right.
        #expect(ThrowSpotGeometry.nearestFlank(for: spot, thrower: .home, category: category, kenei: [0, 0, 2.35]) == .right)
    }

    @Test func throwsAtTheKonHaveNoFlank() {
        #expect(ThrowSpotGeometry.nearestFlank(for: .diagonal(kenei: 0), thrower: .home, category: category, kenei: [-1, 0, 0]) == .right)
        #expect(ThrowSpotGeometry.nearestFlank(for: .line, thrower: .home, category: category, kenei: [-1, 0, 0]) == .right)
    }
}
