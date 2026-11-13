/// A «Бес табан» match between two players, by the Регламент (docs/05-rules.md, §2–3).
/// Pure rules: it knows nothing about positions or physics. The arena reports each throw as
/// `ThrowFacts` and gets back what the referee calls and which kenei go where.
struct BesTabanMatch: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Waiting for both saqas to be spun to see who starts (п. 3.4).
        case iiru
        case playing
        case partiaOver(winner: Player)
        case matchOver(winner: Player)
    }

    let category: AgeCategory
    private(set) var phase = Phase.iiru
    /// 1…3: a match is won by two partii (п. 1.2).
    private(set) var partia = 1
    private(set) var partiaWins: [Player: Int] = [.home: 0, .away: 0]
    /// Kenei out this partia.
    private(set) var score: [Player: Int] = [.home: 0, .away: 0]
    private(set) var thrower = Player.home
    private(set) var spot = ThrowSpot.line
    /// Kenei still on the field this partia.
    private(set) var inPlay: Set<Int>
    /// Who started this partia.
    private(set) var starter = Player.home

    /// The starter's kenei stand on the kon (каз. п. 3.4).
    var keneiOwner: Player { starter }

    init(category: AgeCategory) {
        self.category = category
        inPlay = Set(0..<category.keneiCount)
    }

    // MARK: - Iiru

    /// Settles who starts from how both saqas fell: the higher side (п. 3.4). Returns nil when
    /// they must spin again: equal sides, or ompy and shonqai, which stand outside the ranking.
    @discardableResult
    mutating func settleIiru(home: Side, away: Side) -> Player? {
        guard phase == .iiru, let homeRank = home.rank, let awayRank = away.rank, homeRank != awayRank else {
            return nil
        }
        let winner: Player = homeRank < awayRank ? .home : .away
        starter = winner
        thrower = winner
        spot = .line
        phase = .playing
        return winner
    }

    // MARK: - Throws

    /// Applies a throw that came to rest. Outside `.playing` it changes nothing.
    mutating func record(_ facts: ThrowFacts) -> ThrowOutcome {
        guard phase == .playing else { return ThrowOutcome() }
        // The kenei of a special throw was left lying where it fell. Whenever play moves on
        // without it being knocked out or commanded again, it goes back to its slot.
        let lyingTarget = spot.targetKenei.flatMap { inPlay.contains($0) ? $0 : nil }
        let displaced = Set(facts.displaced.keys).intersection(inPlay)

        // «Сырғытпа»: the throw doesn't count, whatever it knocked out (п. 1.5.2).
        if facts.isSlide {
            var restored = displaced.union(Set(facts.knockedOut).intersection(inPlay))
            if let lyingTarget { restored.insert(lyingTarget) }
            passTurn()
            return ThrowOutcome(calls: [.slide], restored: restored.sorted())
        }

        let out = Set(facts.knockedOut).intersection(inPlay)
        if !out.isEmpty {
            return knock(out, displaced: displaced, lyingTarget: lyingTarget)
        }

        // Nothing out, but the saqa touched a kenei that stayed in the circle: the referee
        // gives one more throw at it (п. 2.1–2.3). The first one it touched decides.
        if let target = facts.touched.first(where: { inPlay.contains($0) && facts.displaced[$0] != nil }),
           let zone = facts.displaced[target] {
            var restored = displaced
            restored.remove(target)
            if let lyingTarget, lyingTarget != target { restored.insert(lyingTarget) }
            // Flank defaults to the right; the controller picks the nearer one with
            // `choose(flank:)`, since only it knows where things lie.
            let call: RefereeCall
            switch zone {
            case .parallel:
                spot = .parallel(kenei: target, flank: .right)
                call = .parallel
            case .nearCircle:
                spot = .besTaban(kenei: target, flank: .right)
                call = .besTaban
            case .middle:
                spot = .diagonal(kenei: target)
                call = .diagonal
            }
            return ThrowOutcome(calls: [call], restored: restored.sorted())
        }

        // A miss: «асык ставится на прежнее место, право выполнения переходит к сопернику» (п. 1.3).
        var restored = displaced
        if let lyingTarget { restored.insert(lyingTarget) }
        passTurn()
        return ThrowOutcome(calls: [.miss], restored: restored.sorted())
    }

    /// Kenei out count for the thrower, who keeps throwing from the circle's edge (п. 1.6),
    /// unless that won the partia.
    private mutating func knock(_ out: Set<Int>, displaced: Set<Int>, lyingTarget: Int?) -> ThrowOutcome {
        score[thrower, default: 0] += out.count
        inPlay.subtract(out)
        // Everything that moved but stayed in goes back (п. 1.3).
        var restored = displaced.subtracting(out)
        if let lyingTarget, !out.contains(lyingTarget) { restored.insert(lyingTarget) }
        var calls: [RefereeCall] = [.out(out.count)]

        if score[thrower, default: 0] >= category.winningCount {
            let winner = thrower
            partiaWins[winner, default: 0] += 1
            calls.append(.partiaWon(winner))
            if partiaWins[winner, default: 0] >= 2 {
                calls.append(.matchWon(winner))
                phase = .matchOver(winner: winner)
            } else {
                phase = .partiaOver(winner: winner)
            }
            spot = .line
        } else {
            spot = .circleEdge
        }
        return ThrowOutcome(calls: calls, removed: out.sorted(), restored: restored.sorted())
    }

    private mutating func passTurn() {
        thrower = thrower.opponent
        spot = .line
    }

    // MARK: - Special throws

    /// «Бес табан» and «Параллель» can come from either side; the player chooses (🟡).
    mutating func switchFlank() {
        switch spot {
        case .besTaban(let kenei, let flank):
            spot = .besTaban(kenei: kenei, flank: flank.other)
        case .parallel(let kenei, let flank):
            spot = .parallel(kenei: kenei, flank: flank.other)
        case .line, .circleEdge, .diagonal:
            break
        }
    }

    /// Sets the side of a «Бес табан» or «Параллель» throw. No-op for other spots.
    mutating func choose(flank: Flank) {
        switch spot {
        case .besTaban(let kenei, _):
            spot = .besTaban(kenei: kenei, flank: flank)
        case .parallel(let kenei, _):
            spot = .parallel(kenei: kenei, flank: flank)
        case .line, .circleEdge, .diagonal:
            break
        }
    }

    // MARK: - Partii

    /// After a partia: the next one on a full kon. The second is started by the other player;
    /// before the third the saqas are spun again (каз. п. 3.4).
    mutating func startNextPartia() {
        guard case .partiaOver = phase else { return }
        partia += 1
        score = [.home: 0, .away: 0]
        inPlay = Set(0..<category.keneiCount)
        spot = .line
        if partia == 2 {
            starter = starter.opponent
            thrower = starter
            phase = .playing
        } else {
            phase = .iiru
        }
    }
}
