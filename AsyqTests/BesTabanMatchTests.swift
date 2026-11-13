import Testing
@testable import Asyq

/// Every rule of docs/05-rules.md, §2–3, as a scenario.
struct BesTabanMatchTests {
    /// A match past the iiru, with `starter` to throw first.
    private func started(_ category: AgeCategory = .eresek, starter: Player = .home) -> BesTabanMatch {
        var match = BesTabanMatch(category: category)
        if starter == .home {
            match.settleIiru(home: .alshy, away: .buk)
        } else {
            match.settleIiru(home: .shik, away: .taike)
        }
        return match
    }

    /// Knocks out `count` kenei in play for the current thrower, one throw.
    private func knock(_ match: inout BesTabanMatch, _ count: Int) -> ThrowOutcome {
        let out = Array(match.inPlay.sorted().prefix(count))
        return match.record(ThrowFacts(knockedOut: out, touched: out))
    }

    // MARK: - Iiru

    @Test func theHigherSideStarts() {
        var match = BesTabanMatch(category: .eresek)
        #expect(match.phase == .iiru)
        #expect(match.settleIiru(home: .taike, away: .alshy) == .away)
        #expect(match.phase == .playing)
        #expect(match.starter == .away)
        #expect(match.thrower == .away)
        #expect(match.spot == .line)
        #expect(match.keneiOwner == .away)
    }

    @Test func bukOutranksShik() {
        var match = BesTabanMatch(category: .eresek)
        #expect(match.settleIiru(home: .buk, away: .shik) == .home)
    }

    @Test(arguments: [
        (Side.alshy, Side.alshy),
        (.buk, .buk),
        (.ompy, .alshy),
        (.taike, .shonqai),
        (.ompy, .shonqai),
    ])
    func equalOrUnrankedSidesSpinAgain(home: Side, away: Side) {
        var match = BesTabanMatch(category: .eresek)
        #expect(match.settleIiru(home: home, away: away) == nil)
        #expect(match.phase == .iiru)
    }

    @Test func throwsBeforeTheIiruChangeNothing() {
        var match = BesTabanMatch(category: .eresek)
        let before = match
        let outcome = match.record(ThrowFacts(knockedOut: [0], touched: [0]))
        #expect(outcome == ThrowOutcome())
        #expect(match == before)
    }

    @Test func aSettledIiruCannotBeSettledAgain() {
        var match = started(starter: .home)
        #expect(match.settleIiru(home: .shik, away: .alshy) == nil)
        #expect(match.starter == .home)
    }

    // MARK: - Series and misses

    @Test func aKnockOutCountsAndTheSeriesGoesOnFromTheEdge() {
        var match = started()
        let outcome = match.record(ThrowFacts(knockedOut: [4, 2], touched: [4], displaced: [6: .middle, 5: .parallel]))
        #expect(outcome.calls == [.out(2)])
        #expect(outcome.removed == [2, 4])
        #expect(outcome.restored == [5, 6])
        #expect(match.score[.home] == 2)
        #expect(match.inPlay == Set(0..<15).subtracting([2, 4]))
        #expect(match.thrower == .home)
        #expect(match.spot == .circleEdge)
    }

    @Test func theSeriesContinuesWhileKnockingOut() {
        var match = started()
        _ = knock(&match, 1)
        _ = knock(&match, 1)
        #expect(match.spot == .circleEdge)
        #expect(match.thrower == .home)
        #expect(match.score[.home] == 2)
    }

    @Test func aMissPutsMovedKeneiBackAndPassesTheTurn() {
        var match = started()
        _ = knock(&match, 1)
        let outcome = match.record(ThrowFacts(displaced: [9: .middle, 3: .parallel]))
        #expect(outcome.calls == [.miss])
        #expect(outcome.restored == [3, 9])
        #expect(outcome.removed.isEmpty)
        #expect(match.thrower == .away)
        #expect(match.spot == .line)
        #expect(match.score[.home] == 1)
    }

    @Test func aKeneiTouchedButNotMovedIsJustAMiss() {
        var match = started()
        let outcome = match.record(ThrowFacts(touched: [7]))
        #expect(outcome.calls == [.miss])
        #expect(match.thrower == .away)
    }

    @Test func aKeneiMovedOnlyByAnotherKeneiEarnsNoCommand() {
        var match = started()
        let outcome = match.record(ThrowFacts(touched: [7], displaced: [8: .middle]))
        #expect(outcome.calls == [.miss])
        #expect(outcome.restored == [8])
        #expect(match.spot == .line)
        #expect(match.thrower == .away)
    }

    // MARK: - «Сырғытпа»

    @Test func aSlideCountsNothing() {
        var match = started()
        let outcome = match.record(ThrowFacts(isSlide: true, knockedOut: [1, 2], touched: [1], displaced: [3: .nearCircle]))
        #expect(outcome.calls == [.slide])
        #expect(outcome.removed.isEmpty)
        #expect(outcome.restored == [1, 2, 3])
        #expect(match.score[.home] == 0)
        #expect(match.inPlay.count == 15)
        #expect(match.thrower == .away)
        #expect(match.spot == .line)
    }

    @Test func aSlideEndsASeries() {
        var match = started()
        _ = knock(&match, 1)
        _ = match.record(ThrowFacts(isSlide: true))
        #expect(match.thrower == .away)
        #expect(match.spot == .line)
        #expect(match.score[.home] == 1)
    }

    @Test func aSlideOnASpecialThrowPutsTheTargetBack() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .middle]))
        let outcome = match.record(ThrowFacts(isSlide: true))
        #expect(outcome.restored == [3])
        #expect(match.thrower == .away)
    }

    // MARK: - Partii and the match

    @Test func eightOfFifteenWinsAnAdultPartia() {
        var match = started()
        _ = knock(&match, 7)
        #expect(match.phase == .playing)
        let outcome = knock(&match, 1)
        #expect(outcome.calls == [.out(1), .partiaWon(.home)])
        #expect(match.phase == .partiaOver(winner: .home))
        #expect(match.partiaWins[.home] == 1)
        #expect(match.spot == .line)
    }

    @Test(arguments: [AgeCategory.bala, .jasospirim, .jigit])
    func sevenOfThirteenWinsAChildrensPartia(category: AgeCategory) {
        var match = started(category)
        #expect(match.inPlay.count == 13)
        _ = knock(&match, 6)
        #expect(match.phase == .playing)
        _ = knock(&match, 1)
        #expect(match.phase == .partiaOver(winner: .home))
    }

    @Test func overshootingTheWinningCountStillWins() {
        var match = started()
        _ = knock(&match, 6)
        let outcome = knock(&match, 3)
        #expect(outcome.calls == [.out(3), .partiaWon(.home)])
        #expect(match.score[.home] == 9)
    }

    @Test func nothingIsRecordedAfterAPartiaEnds() {
        var match = started()
        _ = knock(&match, 8)
        let before = match
        #expect(match.record(ThrowFacts(knockedOut: [14], touched: [14])) == ThrowOutcome())
        #expect(match == before)
    }

    @Test func theOtherPlayerStartsTheSecondPartiaOnAFullKon() {
        var match = started(starter: .home)
        _ = knock(&match, 8)
        match.startNextPartia()
        #expect(match.partia == 2)
        #expect(match.phase == .playing)
        #expect(match.starter == .away)
        #expect(match.thrower == .away)
        #expect(match.keneiOwner == .away)
        #expect(match.score == [.home: 0, .away: 0])
        #expect(match.inPlay.count == 15)
        #expect(match.spot == .line)
        #expect(match.partiaWins[.home] == 1)
    }

    @Test func twoPartiiWinTheMatch() {
        var match = started(starter: .home)
        _ = knock(&match, 8)
        match.startNextPartia()
        // The away player starts partia 2 and misses; home wins it.
        _ = match.record(ThrowFacts())
        #expect(match.thrower == .home)
        _ = knock(&match, 7)
        let outcome = knock(&match, 1)
        #expect(outcome.calls == [.out(1), .partiaWon(.home), .matchWon(.home)])
        #expect(match.phase == .matchOver(winner: .home))
        #expect(match.partiaWins[.home] == 2)
        // Over is over.
        match.startNextPartia()
        #expect(match.phase == .matchOver(winner: .home))
    }

    @Test func aThirdPartiaStartsWithAnotherIiru() {
        var match = started(starter: .home)
        _ = knock(&match, 8)
        match.startNextPartia()
        _ = knock(&match, 8)
        #expect(match.phase == .partiaOver(winner: .away))
        match.startNextPartia()
        #expect(match.partia == 3)
        #expect(match.phase == .iiru)
        #expect(match.inPlay.count == 15)
        #expect(match.settleIiru(home: .shik, away: .buk) == .away)
        #expect(match.starter == .away)
        #expect(match.phase == .playing)
    }

    @Test func aNewPartiaOnlyFollowsAFinishedOne() {
        var match = started()
        let before = match
        match.startNextPartia()
        #expect(match == before)
    }

    // MARK: - The referee's commands

    @Test(arguments: [
        (KeneiZone.parallel, ThrowSpot.parallel(kenei: 3, flank: .right), RefereeCall.parallel),
        (.nearCircle, .besTaban(kenei: 3, flank: .right), .besTaban),
        (.middle, .diagonal(kenei: 3), .diagonal),
    ])
    func eachZoneHasItsCommand(zone: KeneiZone, spot: ThrowSpot, call: RefereeCall) {
        var match = started()
        let outcome = match.record(ThrowFacts(touched: [3], displaced: [3: zone]))
        #expect(outcome.calls == [call])
        #expect(outcome.restored.isEmpty)
        #expect(outcome.removed.isEmpty)
        #expect(match.spot == spot)
        #expect(match.thrower == .home)
        #expect(match.spot.targetKenei == 3)
    }

    @Test func theTargetStaysWhereItFellAndTheRestGoBack() {
        var match = started()
        let outcome = match.record(ThrowFacts(touched: [2], displaced: [2: .middle, 5: .middle, 7: .parallel]))
        #expect(match.spot == .diagonal(kenei: 2))
        #expect(outcome.restored == [5, 7])
    }

    @Test func theFirstTouchedKeneiInAZoneDecides() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [9, 4], displaced: [9: .nearCircle, 4: .parallel]))
        #expect(match.spot == .besTaban(kenei: 9, flank: .right))

        var other = started()
        // 9 was touched first but stayed on its slot: 4 decides.
        let outcome = other.record(ThrowFacts(touched: [9, 4], displaced: [4: .parallel, 11: .middle]))
        #expect(other.spot == .parallel(kenei: 4, flank: .right))
        #expect(outcome.restored == [11])
    }

    @Test func aSpecialThrowThatKnocksOutContinuesTheSeries() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [4], displaced: [4: .middle]))
        // «Диагональ»: the target and a kenei from the kon both go out and both count (п. 2.2).
        let outcome = match.record(ThrowFacts(knockedOut: [4, 7], touched: [4]))
        #expect(outcome.calls == [.out(2)])
        #expect(outcome.removed == [4, 7])
        #expect(outcome.restored.isEmpty)
        #expect(match.score[.home] == 2)
        #expect(match.spot == .circleEdge)
        #expect(match.thrower == .home)
    }

    @Test func aSpecialThrowThatKnocksOutAnotherPutsTheTargetBack() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .parallel]))
        let outcome = match.record(ThrowFacts(knockedOut: [8], touched: [3], displaced: [3: .parallel]))
        #expect(outcome.removed == [8])
        #expect(outcome.restored == [3])
        #expect(match.spot == .circleEdge)
    }

    @Test func aFailedSpecialThrowPutsTheTargetBackAndPassesTheTurn() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .parallel]))
        // Missed it entirely; the judge sees it still lying off its slot.
        let outcome = match.record(ThrowFacts(displaced: [3: .parallel]))
        #expect(outcome.calls == [.miss])
        #expect(outcome.restored == [3])
        #expect(match.thrower == .away)
        #expect(match.spot == .line)
    }

    @Test func aFailedSpecialThrowRestoresTheTargetEvenIfTheJudgeMissedIt() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .middle]))
        let outcome = match.record(ThrowFacts())
        #expect(outcome.restored == [3])
    }

    @Test func commandsChainOnTheSameKenei() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .parallel]))
        let outcome = match.record(ThrowFacts(touched: [3], displaced: [3: .nearCircle]))
        #expect(outcome.calls == [.besTaban])
        #expect(outcome.restored.isEmpty)
        #expect(match.spot == .besTaban(kenei: 3, flank: .right))
        #expect(match.thrower == .home)
    }

    @Test func commandsChainOntoAnotherKeneiAndTheOldTargetGoesBack() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .parallel]))
        let outcome = match.record(ThrowFacts(touched: [6], displaced: [6: .middle, 3: .parallel]))
        #expect(outcome.calls == [.diagonal])
        #expect(outcome.restored == [3])
        #expect(match.spot == .diagonal(kenei: 6))
    }

    @Test func keneiAlreadyOutAreIgnored() {
        var match = started()
        _ = match.record(ThrowFacts(knockedOut: [2], touched: [2]))
        let outcome = match.record(ThrowFacts(knockedOut: [2], touched: [2], displaced: [2: .middle]))
        #expect(outcome.calls == [.miss])
        #expect(outcome.removed.isEmpty)
        #expect(outcome.restored.isEmpty)
        #expect(match.score[.home] == 1)
        #expect(match.thrower == .away)
    }

    @Test func outcomesAreSortedWithoutDuplicates() {
        var match = started()
        let outcome = match.record(ThrowFacts(knockedOut: [9, 1, 9, 5], touched: [9], displaced: [12: .middle, 0: .middle, 1: .middle]))
        #expect(outcome.removed == [1, 5, 9])
        #expect(outcome.restored == [0, 12])
        #expect(match.score[.home] == 3)
    }

    // MARK: - Flanks

    @Test func theFlankOfASpecialThrowCanBeSwitched() {
        var match = started()
        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .parallel]))
        match.switchFlank()
        #expect(match.spot == .parallel(kenei: 3, flank: .left))
        match.switchFlank()
        #expect(match.spot == .parallel(kenei: 3, flank: .right))
        match.choose(flank: .left)
        #expect(match.spot == .parallel(kenei: 3, flank: .left))

        var besTaban = started()
        _ = besTaban.record(ThrowFacts(touched: [5], displaced: [5: .nearCircle]))
        besTaban.switchFlank()
        #expect(besTaban.spot == .besTaban(kenei: 5, flank: .left))
    }

    @Test func throwsAtTheKonHaveNoFlank() {
        var match = started()
        match.switchFlank()
        match.choose(flank: .left)
        #expect(match.spot == .line)

        _ = match.record(ThrowFacts(touched: [3], displaced: [3: .middle]))
        match.switchFlank()
        #expect(match.spot == .diagonal(kenei: 3))
    }
}
