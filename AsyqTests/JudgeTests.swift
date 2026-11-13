import simd
import Testing
@testable import Asyq

/// docs/05-rules.md, question 6: a kenei is out only when all of it is past the line's outer edge.
struct JudgeTests {
    let shape = BoneShape.kenei
    let radius: Float = 2.5
    let lineWidth = FieldGeometry.circleLineWidth

    private func isOut(atDistance distance: Float, side: Side = .buk, direction: SIMD2<Float> = [1, 0]) -> Bool {
        let rotation = shape.restingRotation(side)
        let position = SIMD3(direction.x * distance, shape.restingHeight(rotation: rotation), direction.y * distance)
        return Judge.isKnockedOut(position: position, rotation: rotation, shape: shape, circleRadius: radius)
    }

    @Test func onTheKonIsIn() {
        #expect(!isOut(atDistance: 0))
        #expect(!isOut(atDistance: 0.4))
    }

    @Test func touchingTheLineIsIn() {
        // Its center is past the line, but its near end still touches the outer edge.
        let reach = shape.halfExtents.x
        #expect(!isOut(atDistance: radius + lineWidth / 2 + reach - 0.002))
    }

    @Test func whollyPastTheLineIsOut() {
        let reach = shape.halfExtents.x
        #expect(isOut(atDistance: radius + lineWidth / 2 + reach + 0.002))
    }

    @Test func lyingAcrossTheRadiusItReachesLess() {
        // Just past the line by more than its width but less than its length.
        let distance = radius + lineWidth / 2 + shape.halfExtents.z + 0.003
        // Length along the radius: its near end still touches the line.
        #expect(!isOut(atDistance: distance, side: .buk, direction: [1, 0]))
        // Turned a quarter, it reaches back only its width: out.
        let across = shape.restingRotation(.buk, yaw: .pi / 2)
        let position = SIMD3<Float>(distance, shape.halfExtents.y, 0)
        #expect(Judge.isKnockedOut(position: position, rotation: across, shape: shape, circleRadius: radius))
    }

    @Test func everyDirectionCounts() {
        for angle in stride(from: Float(0), to: 6.2, by: 0.5) {
            let direction = SIMD2(cos(angle), sin(angle))
            #expect(isOut(atDistance: radius + 0.2, direction: direction))
            #expect(!isOut(atDistance: radius - 0.2, direction: direction))
        }
    }

    // MARK: - Zones for the referee's commands

    private func zone(_ x: Float, _ z: Float, _ category: AgeCategory = .eresek) -> KeneiZone {
        Judge.zone(of: SIMD3(x, 0.01, z), category: category)
    }

    @Test func betweenTheParallelLinesAlongTheKonIsParallel() {
        #expect(zone(0, 0) == .parallel)
        #expect(zone(0.5, 0.15) == .parallel)
        #expect(zone(-0.575, -0.15) == .parallel)
    }

    @Test func pastTheParallelLinesOrTheKonsEndsIsNot() {
        #expect(zone(0.5, 0.151) == .middle)
        #expect(zone(0.576, 0) == .middle)
        // The kids' kon is shorter: 110 cm.
        #expect(zone(0.56, 0, .bala) == .middle)
        #expect(zone(0.54, 0, .bala) == .parallel)
    }

    @Test func withinATabanOfTheCircleLineIsBesTaban() {
        let edge = radius - GameTuning.Rules.taban
        #expect(zone(0, edge + 0.001) == .nearCircle)
        #expect(zone(0, edge - 0.001) == .middle)
        #expect(zone(-(edge + 0.01) / Float(2).squareRoot(), (edge + 0.01) / Float(2).squareRoot()) == .nearCircle)
        // The kids' circle is smaller.
        #expect(zone(0, 1.3, .bala) == .nearCircle)
        #expect(zone(0, 1.2, .bala) == .middle)
    }

    @Test func landingShortOutsideTheCircleIsASlide() {
        let spot = SIMD3<Float>(0, 0, 6)
        #expect(Judge.isSlide(landing: [0, 0, 3.5], spot: spot, target: .zero, category: .eresek))
        #expect(!Judge.isSlide(landing: [0, 0, 2.0], spot: spot, target: .zero, category: .eresek))
    }

    @Test func overshootingBeyondTheFarSideIsNoSlide() {
        let spot = SIMD3<Float>(0, 0, 6)
        #expect(!Judge.isSlide(landing: [0, 0, -3.5], spot: spot, target: .zero, category: .eresek))
        // The rival throws the other way.
        #expect(Judge.isSlide(landing: [0, 0, -3.5], spot: [0, 0, -6], target: .zero, category: .eresek))
    }
}
