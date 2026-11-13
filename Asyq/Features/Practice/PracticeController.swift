import Foundation
import Observation
import simd

/// Free practice: throw at the kon, knock kenei out, keep the series going from the circle's
/// edge (Регламент, п. 1.6). No rival, no special commands: just the throw.
@Observable
@MainActor
final class PracticeController {
    private(set) var banner: RefereeBanner?
    private(set) var knockedOut = 0
    private(set) var isFromEdge = false
    private(set) var showsHint = true
    let category: AgeCategory
    let stage: ArenaStage

    @ObservationIgnored private var bannerSerial = 0
    @ObservationIgnored private var nextTurnTask: Task<Void, Never>?

    init(category: AgeCategory = .eresek) {
        self.category = category
        stage = ArenaStage(category: category)
        stage.onEvent = { [weak self] event in self?.handle(event) }
        if DebugLaunchArguments.fromEdge { isFromEdge = true }
        aimNext()
        runDebugThrow()
    }

    var spot: ThrowSpot { isFromEdge ? .circleEdge : .line }

    var throwDistance: Float {
        isFromEdge ? category.circleRadius : category.throwDistance
    }

    /// A fresh kon from the line, score cleared.
    func restart() {
        guard stage.canPull else { return }
        nextTurnTask?.cancel()
        banner = nil
        knockedOut = 0
        isFromEdge = false
        stage.resetKon(animated: true)
        aimNext()
    }

    private func aimNext() {
        let place = ThrowSpotGeometry.place(spot, thrower: .home, category: category, kenei: nil)
        stage.aim(ArenaStage.Aim(spot: place.spot, target: place.target, framingWidth: KonLayout.rowWidth(category), thrower: .home))
    }

    private func handle(_ event: ArenaStage.Event) {
        guard case .settled(let facts, let saqaSide) = event else { return }
        showsHint = false
        let call: RefereeCall
        if facts.isSlide {
            call = .slide
            stage.restore(kenei: facts.knockedOut + Array(facts.displaced.keys))
            isFromEdge = false
        } else if facts.knockedOut.isEmpty {
            call = .miss
            stage.restore(kenei: Array(facts.displaced.keys))
            isFromEdge = false
        } else {
            call = .out(facts.knockedOut.count)
            knockedOut += facts.knockedOut.count
            stage.remove(kenei: facts.knockedOut)
            stage.restore(kenei: Array(facts.displaced.keys))
            isFromEdge = true
        }
        bannerSerial += 1
        banner = RefereeBanner(call: call, saqaSide: saqaSide, serial: bannerSerial)
        nextTurnTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GameTuning.Result.bannerTime))
            guard !Task.isCancelled else { return }
            self?.nextTurn()
        }
    }

    private func nextTurn() {
        banner = nil
        let remaining = (0..<stage.keneiCount).filter { stage.isOnField(kenei: $0) }
        if remaining.isEmpty {
            knockedOut = 0
            isFromEdge = false
            stage.resetKon(animated: true)
        }
        aimNext()
    }

    private func runDebugThrow() {
        guard let input = DebugLaunchArguments.throwInput else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.stage.throwSaqa(input)
        }
    }
}
