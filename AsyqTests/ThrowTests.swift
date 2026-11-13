import CoreGraphics
import simd
import Testing
@testable import Asyq

struct ThrowGestureTests {
    @Test func pullingStraightDownIsPowerWithoutAim() {
        var gesture = ThrowGesture(start: CGPoint(x: 200, y: 400))
        gesture.current = CGPoint(x: 200, y: 400 + GameTuning.Gesture.fullPull / 2)
        #expect(abs(gesture.power - 0.5) < 1e-9)
        #expect(gesture.aim == 0)
    }

    @Test func pullingLeftAimsRightLikeASlingshot() {
        var gesture = ThrowGesture(start: CGPoint(x: 200, y: 400))
        gesture.current = CGPoint(x: 150, y: 600)
        #expect(gesture.aim > 0)
        #expect(gesture.input.angle > 0)
    }

    @Test func powerAndAimAreClamped() {
        var gesture = ThrowGesture(start: .zero)
        gesture.current = CGPoint(x: -5000, y: 5000)
        #expect(gesture.power == 1)
        #expect(gesture.aim == 1)
        #expect(abs(gesture.input.angle - GameTuning.Throw.maxAimAngle) < 1e-6)
    }

    @Test func aShortPullIsCancelled() {
        var gesture = ThrowGesture(start: .zero)
        gesture.current = CGPoint(x: 3, y: 8)
        #expect(gesture.release(velocity: .zero) == nil)
    }

    @Test func pushingUpIsNotAThrow() {
        var gesture = ThrowGesture(start: CGPoint(x: 0, y: 400))
        gesture.current = CGPoint(x: 0, y: 200)
        #expect(gesture.release(velocity: .zero) == nil)
    }

    @Test func aFlickGivesSpinAndAStillReleaseDoesNot() throws {
        var gesture = ThrowGesture(start: .zero)
        gesture.current = CGPoint(x: 0, y: 150)
        let still = try #require(gesture.release(velocity: CGVector(dx: 100, dy: 0)))
        #expect(still.spin == 0)
        let flicked = try #require(gesture.release(velocity: CGVector(dx: 1500, dy: 0)))
        #expect(flicked.spin > 0.5)
    }
}

struct ThrowLaunchTests {
    let spot = SIMD3<Float>(0, 0, 6)
    let target = SIMD3<Float>(0, 0, 0)

    @Test(arguments: [Float(0.2), 0.5, 0.63, 0.9])
    func theFlightLandsWherePowerSays(power: Float) throws {
        let input = ThrowInput(angle: 0, power: power)
        let launch = ThrowLaunch(input: input, release: ThrowLaunch.releasePoint(spot: spot, target: target), spot: spot, target: target)
        let landing = try #require(launch.trajectory(samples: 200).last)
        let travelled = simd_length(SIMD2(landing.x - spot.x, landing.z - spot.z))
        #expect(abs(travelled - input.range) < 0.03)
        #expect(abs(landing.y) < 1e-3)
    }

    @Test func aimTurnsTheThrowToTheRight() {
        let input = ThrowInput(angle: GameTuning.Throw.maxAimAngle, power: 0.6)
        let launch = ThrowLaunch(input: input, release: ThrowLaunch.releasePoint(spot: spot, target: target), spot: spot, target: target)
        // Throwing toward −z, the thrower's right is +x.
        #expect(launch.direction.x > 0)
        #expect(launch.linearVelocity.z < 0)
    }

    @Test func theHandLetsGoBehindTheLine() {
        let release = ThrowLaunch.releasePoint(spot: spot, target: target)
        #expect(release.z > spot.z)
        #expect(release.y > 0.2 && release.y < 0.6)
    }

    @Test func inputsOutOfRangeAreClamped() {
        let input = ThrowInput(angle: 1, power: 3, spin: -9)
        #expect(input.angle == GameTuning.Throw.maxAimAngle)
        #expect(input.power == 1)
        #expect(input.spin == -1)
    }
}
