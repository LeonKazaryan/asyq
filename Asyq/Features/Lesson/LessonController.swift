import Foundation
import Observation
import simd

/// «How to play»: a short lesson on the real arena. Meet the bones, throw (steadied, so the
/// first throws reach the kon), learn «шықты» and the series, «тимеді», how to win, spin
/// once, and see the referee's three commands (docs/02-design.md, «Первые 60 секунд»).
@Observable
@MainActor
final class LessonController {
    enum Step: Hashable {
        case meet
        case firstThrow
        case shyqty
        case series
        case seriesResult(knockedOut: Bool)
        case timedi
        case syrgytpa
        case goal
        case iiru
        case iiruResult(Side)
        case commands
        case done

        /// Where the progress dots stand.
        var progress: Int {
            switch self {
            case .meet: 0
            case .firstThrow, .timedi, .syrgytpa: 1
            case .shyqty, .series: 2
            case .seriesResult: 3
            case .goal: 4
            case .iiru, .iiruResult: 5
            case .commands: 6
            case .done: 7
            }
        }

        static let count = 8

        var isThrow: Bool {
            self == .firstThrow || self == .series
        }
    }

    nonisolated static let completedKey = "lesson.completed"

    nonisolated static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    private(set) var step = Step.meet {
        didSet { if DebugLaunchArguments.autoplay { autoplay() } }
    }
    private(set) var banner: RefereeBanner?
    /// How much the player's throw is steadied toward a kenei, 0…1.
    @ObservationIgnored private var assist: Float = 0.85
    @ObservationIgnored private var bannerSerial = 0
    @ObservationIgnored private var pending: [Task<Void, Never>] = []
    let category = AgeCategory.bala
    let stage: ArenaStage

    init() {
        stage = ArenaStage(category: category)
        stage.onEvent = { [weak self] event in self?.handle(event) }
        stage.inputAssist = { [weak self] input, aim in
            self?.steady(input, aim: aim) ?? input
        }
        aim(from: .line)
        if DebugLaunchArguments.autoplay { autoplay() }
    }

    /// Debug (`-AsyqDebugAutoplay YES`): reads each card for a moment, then moves on by itself.
    private func autoplay() {
        let current = step
        after(current.isThrow || current == .iiru ? 1.6 : 3.2) { [weak self] in
            guard let self, step == current else { return }
            switch current {
            case .firstThrow, .series:
                guard let aim = stage.aim else { return }
                stage.throwSaqa(steady(ThrowInput(angle: 0.01, power: 0.5), aim: aim))
            case .iiru:
                spin(strength: 0.7, tilt: 0.2)
            case .done:
                break
            default:
                next()
            }
        }
    }

    var canSpin: Bool {
        step == .iiru
    }

    // MARK: - Moving on

    /// The card's button.
    func next() {
        switch step {
        case .meet:
            step = .firstThrow
        case .shyqty:
            assist = 0.6
            aim(from: .circleEdge)
            step = .series
        case .timedi, .syrgytpa:
            aim(from: .line)
            step = .firstThrow
        case .seriesResult:
            step = .goal
        case .goal:
            stage.beginIiru()
            TermFamiliarity.markSeen(.iiru)
            step = .iiru
        case .iiruResult:
            stage.endIiru()
            aim(from: .line)
            step = .commands
        case .commands:
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            step = .done
        case .firstThrow, .series, .iiru, .done:
            break
        }
    }

    func spin(strength: Float, tilt: Float) {
        guard canSpin else { return }
        stage.spinIiru(.home, strength: strength, tilt: tilt)
    }

    func stop() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
    }

    // MARK: - The arena

    private func aim(from spot: ThrowSpot) {
        let place = ThrowSpotGeometry.place(spot, thrower: .home, category: category, kenei: nil)
        stage.aim(ArenaStage.Aim(spot: place.spot, target: place.target, framingWidth: KonLayout.rowWidth(category), thrower: .home))
    }

    private func handle(_ event: ArenaStage.Event) {
        switch event {
        case .iiruSettled(let sides):
            guard step == .iiru, let side = sides[.home] else { return }
            after(1.0) { [weak self] in self?.step = .iiruResult(side) }
        case .settled(let facts, let saqaSide):
            guard step.isThrow else { return }
            settle(facts, saqaSide: saqaSide)
        }
    }

    private func settle(_ facts: ThrowFacts, saqaSide: Side?) {
        let call: RefereeCall
        let next: Step
        if facts.isSlide {
            call = .slide
            stage.restore(kenei: facts.knockedOut + Array(facts.displaced.keys))
            next = step == .series ? .seriesResult(knockedOut: false) : .syrgytpa
        } else if facts.knockedOut.isEmpty {
            call = .miss
            stage.restore(kenei: Array(facts.displaced.keys))
            next = step == .series ? .seriesResult(knockedOut: false) : .timedi
            assist = min(assist + 0.1, 0.95)
        } else {
            call = .out(facts.knockedOut.count)
            stage.remove(kenei: facts.knockedOut)
            stage.restore(kenei: Array(facts.displaced.keys))
            next = step == .series ? .seriesResult(knockedOut: true) : .shyqty
        }
        bannerSerial += 1
        banner = RefereeBanner(call: call, saqaSide: saqaSide, serial: bannerSerial)
        after(GameTuning.Result.bannerTime) { [weak self] in
            self?.banner = nil
            self?.step = next
        }
    }

    /// Steadies a throw toward the kenei nearest to where the player aimed, and toward the
    /// power that reaches it: the lesson is about the rules, not about missing.
    private func steady(_ input: ThrowInput, aim: ArenaStage.Aim) -> ThrowInput {
        var forward = aim.target - aim.spot
        forward.y = 0
        let axis = SimMath.length(forward)
        guard axis > 0 else { return input }
        forward /= axis
        let right = SimMath.cross(forward, [0, 1, 0])
        let angles = (0..<stage.keneiCount).compactMap { index -> (angle: Float, along: Float)? in
            guard stage.isOnField(kenei: index), let position = stage.position(ofKenei: index) else { return nil }
            let lateral = SimMath.dot(position - aim.spot, right)
            let along = SimMath.dot(position - aim.spot, forward)
            return (lateral / along, along)
        }
        guard let nearest = angles.min(by: { abs($0.angle - input.angle) < abs($1.angle - input.angle) }) else { return input }
        let share = nearest.along / axis * (1 + GameTuning.Rival.overshoot)
        let ideal = (share - GameTuning.Throw.minRangeShare) / (GameTuning.Throw.maxRangeShare - GameTuning.Throw.minRangeShare)
        return ThrowInput(
            angle: input.angle + (nearest.angle - input.angle) * assist,
            power: input.power + (ideal - input.power) * assist,
            spin: input.spin
        )
    }

    private func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        pending.removeAll { $0.isCancelled }
        pending.append(Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }
}
