import Foundation
import Observation
import simd

/// A «Бес табан» match against the rival: иіру for who starts, turns, series, the referee's
/// commands, partia and match (docs/05-rules.md). The rules live in `BesTabanMatch`; this
/// drives the arena and the HUD from them.
@Observable
@MainActor
final class MatchController {
    /// The moment of the match the HUD is showing.
    enum Moment: Equatable {
        /// Who starts: the home player flicks, then the rival.
        case iiru(IiruRound)
        case playing
        case partiaOver(winner: Player)
        case matchOver(winner: Player)
    }

    struct IiruRound: Equatable {
        var home: Side?
        var away: Side?
        /// Set once both saqas lie: who starts, or nil for a tie that needs another spin.
        var decided: Player??
        var isHomeSpinning = false
        /// «Иіру» as this player reads it, fixed for the round.
        var headline = TermHeadline(.iiru, learned: TermFamiliarity.isLearned(.iiru))
    }

    private(set) var moment = Moment.iiru(IiruRound())
    /// «Жеңіс» or «Жеңіліс» at the end, as this player reads it.
    private(set) var finalHeadline: TermHeadline?
    private(set) var match: BesTabanMatch
    private(set) var banner: RefereeBanner?
    /// Shown briefly when the turn changes hands.
    private(set) var turnNotice: Player?
    private(set) var showsHint = true
    /// A one-time tip on screen.
    private(set) var tip: MatchTip?
    let category: AgeCategory
    let stage: ArenaStage
    let rivalName: String

    @ObservationIgnored private var rival: RivalBot
    /// Debug: plays the home side too (`-AsyqDebugAutoplay YES`).
    @ObservationIgnored private var autopilot: RivalBot?
    @ObservationIgnored private var bannerSerial = 0
    @ObservationIgnored private var pending: [Task<Void, Never>] = []

    init(category: AgeCategory, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.category = category
        match = BesTabanMatch(category: category)
        stage = ArenaStage(category: category)
        rivalName = Names.rival
        rival = RivalBot(name: rivalName, seed: seed)
        stage.onEvent = { [weak self] event in self?.handle(event) }
        if DebugLaunchArguments.autoplay {
            autopilot = RivalBot(name: "Autopilot", seed: seed &+ 1)
        }
        beginIiruRound()
    }

    /// A fresh round of иіру: both saqas off the carpet, the camera down to it.
    private func beginIiruRound() {
        moment = .iiru(IiruRound())
        TermFamiliarity.markSeen(.iiru)
        stage.beginIiru()
        autoSpinIfNeeded()
    }

    private func autoSpinIfNeeded() {
        let debugSpin = DebugLaunchArguments.spin
        guard debugSpin != nil || autopilot != nil else { return }
        schedule(after: 1.2) { [weak self] in
            guard let self else { return }
            let chosen = debugSpin ?? autopilot?.chooseSpin() ?? (0.7, 0)
            spin(strength: chosen.strength, tilt: chosen.tilt)
        }
    }

    func name(of player: Player) -> String {
        player == .home ? String(localized: "You") : rivalName
    }

    /// The distance of the current throw, spot to target.
    var throwDistance: Float {
        guard let aim = stage.aim else { return category.throwDistance }
        return simd_length(SIMD2(aim.spot.x - aim.target.x, aim.spot.z - aim.target.z))
    }

    var canSwitchFlank: Bool {
        guard moment == .playing, match.thrower == .home, stage.canPull, stage.pullPower == nil else { return false }
        switch match.spot {
        case .besTaban, .parallel: return true
        default: return false
        }
    }

    // MARK: - Иіру

    var canSpin: Bool {
        guard case .iiru(let round) = moment else { return false }
        return round.home == nil && !round.isHomeSpinning
    }

    /// The home player's flick: spins their saqa.
    func spin(strength: Float, tilt: Float) {
        guard canSpin, case .iiru(var round) = moment else { return }
        round.isHomeSpinning = true
        moment = .iiru(round)
        stage.spinIiru(.home, strength: strength, tilt: tilt)
    }

    private func settleIiru(_ sides: [Player: Side]) {
        guard case .iiru(var round) = moment else { return }
        if round.home == nil, let home = sides[.home] {
            round.home = home
            round.isHomeSpinning = false
            moment = .iiru(round)
            // The rival spins a moment later, beside it.
            schedule(after: 0.7) { [weak self] in
                guard let self else { return }
                let spin = rival.chooseSpin()
                stage.spinIiru(.away, strength: spin.strength, tilt: spin.tilt)
            }
            return
        }
        guard let home = round.home, let away = sides[.away] else { return }
        round.away = away
        let starter = match.settleIiru(home: home, away: away)
        round.decided = .some(starter)
        moment = .iiru(round)
        schedule(after: 2.4) { [weak self] in
            guard let self else { return }
            if starter == nil {
                beginIiruRound()
            } else {
                stage.endIiru()
                startPlaying()
            }
        }
    }

    // MARK: - Playing

    private func startPlaying() {
        moment = .playing
        aimNext(announceTurn: true)
    }

    /// The other place a special throw may come from.
    func switchFlank() {
        guard canSwitchFlank else { return }
        match.switchFlank()
        aimNext(announceTurn: false)
    }

    private func aimNext(announceTurn: Bool) {
        let spot = match.spot
        let thrower = match.thrower
        let kenei = spot.targetKenei.flatMap { stage.position(ofKenei: $0) }
        let place = ThrowSpotGeometry.place(spot, thrower: thrower, category: category, kenei: kenei)
        stage.aim(ArenaStage.Aim(
            spot: place.spot,
            target: place.target,
            framingWidth: spot.targetKenei == nil ? KonLayout.rowWidth(category) : GameTuning.Camera.singleKeneiFraming,
            thrower: thrower,
            // docs/research/game-design.md: no trajectory hint for adults, as in life.
            showsGuide: category != .eresek,
            targetKenei: spot.targetKenei
        ))
        offerTip(for: spot, thrower: thrower)
        if announceTurn {
            turnNotice = thrower
            schedule(after: 1.4) { [weak self] in self?.turnNotice = nil }
        }
        if thrower == .away {
            schedule(after: GameTuning.Rival.thinkTime) { [weak self] in
                guard let self, moment == .playing, match.thrower == .away else { return }
                stage.throwSaqa(rival.chooseThrow(spot: place.spot, target: place.target, kenei: targets(for: spot, place: place)))
            }
        } else if autopilot != nil {
            schedule(after: GameTuning.Rival.thinkTime) { [weak self] in
                guard let self, moment == .playing, match.thrower == .home, var autopilot else { return }
                stage.throwSaqa(autopilot.chooseThrow(spot: place.spot, target: place.target, kenei: targets(for: spot, place: place)))
                self.autopilot = autopilot
            }
        }
    }

    /// What a bot may aim at: the special throw's kenei, or every kenei still on the kon.
    private func targets(for spot: ThrowSpot, place: (spot: SIMD3<Float>, target: SIMD3<Float>)) -> [SIMD3<Float>] {
        if spot.targetKenei != nil { return [place.target] }
        return (0..<stage.keneiCount).compactMap { index in
            match.inPlay.contains(index) ? stage.position(ofKenei: index) : nil
        }
    }

    /// The first time the player meets a series, the rival's turn or a referee's command.
    private func offerTip(for spot: ThrowSpot, thrower: Player) {
        let candidate: MatchTip? = switch (spot, thrower) {
        case (.circleEdge, .home): .series
        case (.line, .away): .rivalTurn
        case (.besTaban, .home): .besTaban
        case (.diagonal, .home): .diagonal
        case (.parallel, .home): .parallel
        default: nil
        }
        show(candidate)
    }

    private func show(_ candidate: MatchTip?) {
        guard autopilot == nil, let candidate, !candidate.hasBeenShown else { return }
        candidate.markShown()
        tip = candidate
    }

    func dismissTip() {
        tip = nil
    }

    private func settleThrow(_ facts: ThrowFacts, saqaSide: Side?) {
        tip = nil
        if match.thrower == .home, facts.isSlide {
            schedule(after: GameTuning.Result.bannerTime) { [weak self] in self?.show(.slide) }
        }
        if match.thrower == .home { showsHint = false }
        let previousThrower = match.thrower
        let outcome = match.record(facts)
        #if DEBUG
        print("[match] t=\(Date().timeIntervalSince1970) \(previousThrower) calls=\(outcome.calls) next=\(match.spot) score=\(match.score) partia=\(match.partia)")
        #endif
        stage.remove(kenei: outcome.removed)
        stage.restore(kenei: outcome.restored)
        if let call = outcome.calls.first {
            bannerSerial += 1
            banner = RefereeBanner(call: call, saqaSide: saqaSide, serial: bannerSerial)
        }
        schedule(after: GameTuning.Result.bannerTime) { [weak self] in
            guard let self else { return }
            banner = nil
            switch match.phase {
            case .partiaOver(let winner):
                moment = .partiaOver(winner: winner)
                if autopilot != nil {
                    schedule(after: 2) { [weak self] in self?.continueAfterPartia() }
                }
            case .matchOver(let winner):
                let term: Term = winner == .home ? .zhenis : .zhenilis
                finalHeadline = TermHeadline(term, learned: TermFamiliarity.isLearned(term), exclaimed: winner == .home)
                TermFamiliarity.markSeen(term)
                moment = .matchOver(winner: winner)
            case .playing:
                // A command picks the nearer side by default; the player may switch.
                if let target = match.spot.targetKenei, let position = stage.position(ofKenei: target) {
                    defaultFlank(near: position)
                }
                aimNext(announceTurn: match.thrower != previousThrower)
            case .iiru:
                break
            }
        }
    }

    private func defaultFlank(near position: SIMD3<Float>) {
        let nearest = ThrowSpotGeometry.nearestFlank(for: match.spot, thrower: match.thrower, category: category, kenei: position)
        match.choose(flank: nearest)
    }

    /// After a partia: the next one, with иіру again before the third.
    func continueAfterPartia() {
        guard case .partiaOver = moment else { return }
        match.startNextPartia()
        stage.resetKon(animated: true)
        if match.phase == .iiru {
            beginIiruRound()
        } else {
            startPlaying()
        }
    }

    // MARK: - Events

    private func handle(_ event: ArenaStage.Event) {
        switch event {
        case .iiruSettled(let sides):
            settleIiru(sides)
        case .settled(let facts, let saqaSide):
            guard moment == .playing else { return }
            settleThrow(facts, saqaSide: saqaSide)
        }
    }

    private func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) {
        pending.removeAll { $0.isCancelled }
        pending.append(Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }

    /// Leaving the match: nothing scheduled may fire afterwards.
    func stop() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
    }
}
