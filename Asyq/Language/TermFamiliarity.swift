import Foundation

/// How well the player knows each word. A call shows its meaning first and the Kazakh word
/// beside it; once seen `learnedAfter` times, the word leads and the meaning steps back.
enum TermFamiliarity {
    static let learnedAfter = 3

    static func isLearned(_ term: Term) -> Bool {
        TermLanguage.current == .kazakh || timesSeen(term) >= learnedAfter
    }

    static func markSeen(_ term: Term) {
        UserDefaults.standard.set(timesSeen(term) + 1, forKey: key(term))
    }

    static func timesSeen(_ term: Term) -> Int {
        UserDefaults.standard.integer(forKey: key(term))
    }

    /// Forgets everything, as for a new player.
    static func reset() {
        for term in Term.allCases {
            UserDefaults.standard.removeObject(forKey: key(term))
        }
    }

    private static func key(_ term: Term) -> String {
        "term.seen.\(term.rawValue)"
    }
}

/// A term as a headline with a line under it: the meaning with the word, or the word with
/// the meaning, depending on whether the player knows it yet.
struct TermHeadline: Equatable {
    var title: String
    var detail: String

    /// - Parameters:
    ///   - detail: what to say under the word once it's known; the term's meaning if nil.
    ///   - exclaimed: a call, shouted: «ШЫҚТЫ!».
    init(_ term: Term, learned: Bool, detail knownDetail: LocalizedStringResource? = nil, exclaimed: Bool = false) {
        let mark = exclaimed ? "!" : ""
        if learned {
            title = term.word.uppercased() + mark
            detail = String(localized: knownDetail ?? term.call)
        } else {
            title = String(localized: term.call).uppercased()
            detail = Self.wordWithGloss(term)
        }
    }

    /// «Shyqty — “it's out”».
    static func wordWithGloss(_ term: Term) -> String {
        let gloss = String(localized: term.gloss)
        return String(localized: "\(term.word) — “\(gloss)”")
    }
}
