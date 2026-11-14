import Testing
@testable import Asyq

/// The progressive Kazakh words (docs/02-design.md, «Обучение»).
@MainActor
@Suite(.serialized)
struct LanguageTests {
    @Test func everyTermHasBothSpellings() {
        for term in Term.allCases {
            #expect(!term.kazakh.isEmpty)
            #expect(!term.latin.isEmpty)
            // Latin spellings are for readers who can't read Cyrillic: plain ASCII letters.
            #expect(term.latin.allSatisfy { $0.isASCII }, "\(term)")
        }
    }

    @Test func everySideIsATerm() {
        for side in Side.allCases {
            #expect(Term(side).rawValue == side.rawValue)
        }
    }

    @Test func aNewWordLeadsWithItsMeaningThenTakesOver() {
        guard TermLanguage.current != .kazakh else { return }
        TermFamiliarity.reset()
        let fresh = TermHeadline(.shyqty, learned: TermFamiliarity.isLearned(.shyqty), exclaimed: true)
        #expect(fresh.title == String(localized: Term.shyqty.call).uppercased())
        #expect(fresh.detail.contains(Term.shyqty.word))
        for _ in 0..<TermFamiliarity.learnedAfter {
            TermFamiliarity.markSeen(.shyqty)
        }
        #expect(TermFamiliarity.isLearned(.shyqty))
        let known = TermHeadline(.shyqty, learned: true, exclaimed: true)
        #expect(known.title == Term.shyqty.word.uppercased() + "!")
        TermFamiliarity.reset()
    }

    @Test func aBannerCountsItsWordAsSeen() {
        TermFamiliarity.reset()
        _ = RefereeBanner(call: .miss, saqaSide: nil, serial: 1)
        #expect(TermFamiliarity.timesSeen(.timedi) == 1)
        TermFamiliarity.reset()
    }

    @Test(arguments: [RefereeCall.out(2), .miss, .slide, .besTaban, .diagonal, .parallel])
    func everyCallHasAWord(call: RefereeCall) {
        #expect(!call.term.kazakh.isEmpty)
        #expect(!String(localized: call.detail).isEmpty)
    }

    @Test func tipsAreShownOnce() {
        MatchTip.reset()
        #expect(!MatchTip.series.hasBeenShown)
        MatchTip.series.markShown()
        #expect(MatchTip.series.hasBeenShown)
        MatchTip.reset()
    }
}
