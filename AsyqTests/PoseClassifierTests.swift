import simd
import Testing
@testable import Asyq

struct PoseClassifierTests {
    @Test(arguments: Side.allCases)
    func restingOnASideReadsAsThatSide(side: Side) {
        let rotation = BoneShape.kenei.restingRotation(side)
        #expect(PoseClassifier.side(of: rotation, shape: .kenei) == side)
    }

    @Test(arguments: Side.allCases)
    func turningAboutTheVerticalChangesNothing(side: Side) {
        for yaw in stride(from: Float(0), to: 6.2, by: 0.7) {
            let rotation = BoneShape.saqa.restingRotation(side, yaw: yaw)
            #expect(PoseClassifier.side(of: rotation, shape: .saqa) == side)
        }
    }

    @Test func aTiltedBoneReadsAsTheNearestSide() {
        // Alshy, leaning 30° toward buk: still alshy.
        let lean = SimMath.rotation(angle: 30 * .pi / 180, axis: [1, 0, 0])
        let rotation = SimMath.multiply(lean, BoneShape.kenei.restingRotation(.alshy))
        #expect(PoseClassifier.side(of: rotation, shape: .kenei) == .alshy)
    }

    @Test func ranksFollowTheRegulation() {
        let ranked = Side.allCases.compactMap { side in side.rank.map { (side, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
        #expect(ranked == [.alshy, .taike, .buk, .shik])
        #expect(Side.ompy.rank == nil && Side.shonqai.rank == nil)
    }

    @Test func restingHeightIsHalfTheThicknessOnAWideSide() {
        let shape = BoneShape.kenei
        #expect(abs(shape.restingHeight(rotation: shape.restingRotation(.buk)) - shape.halfExtents.y) < 1e-6)
        #expect(abs(shape.restingHeight(rotation: shape.restingRotation(.alshy)) - shape.halfExtents.z) < 1e-6)
    }
}
