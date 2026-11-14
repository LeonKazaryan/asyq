import Foundation

/// A tip shown once, the first time something happens in a match (docs/02-design.md: one
/// hint at a time, when it's needed).
enum MatchTip: String, CaseIterable {
    case series, rivalTurn, slide, besTaban, diagonal, parallel

    /// The word the tip is about, if any.
    var term: Term? {
        switch self {
        case .series: .shyqty
        case .rivalTurn: .kezek
        case .slide: .syrgytpa
        case .besTaban: .besTaban
        case .diagonal: .diagonal
        case .parallel: .parallel
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .series: "Your series"
        case .rivalTurn: "Your rival's turn"
        case .slide: "That one didn't count"
        case .besTaban, .diagonal, .parallel: "One more throw"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .series: "You knocked one out, so you throw again — closer now, from the circle's edge. Keep it going!"
        case .rivalTurn: "You missed, so the turn passes. Watch how they throw: you share the same kon, and whoever knocks out more first wins the round."
        case .slide: "Your saqa touched the carpet before the circle and slid in. Pull a little harder so it flies into the circle."
        case .besTaban: "Your saqa hit a kenei that stayed just inside the line. Throw at the glowing kenei from five feet along the circle. ⇄ switches sides."
        case .diagonal: "Your saqa hit a kenei that stayed inside. Throw at the glowing kenei from the far side, across the kon — if you knock out a kon kenei too, both count."
        case .parallel: "Your saqa hit a kenei that stayed between the parallel lines. Throw at the glowing kenei from the circle's wing. ⇄ switches sides."
        }
    }

    /// The command to sketch beside the tip.
    var command: RefereeCall? {
        switch self {
        case .besTaban: .besTaban
        case .diagonal: .diagonal
        case .parallel: .parallel
        default: nil
        }
    }

    var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    func markShown() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func reset() {
        for tip in allCases { UserDefaults.standard.removeObject(forKey: tip.key) }
    }

    private var key: String { "tip.shown.\(rawValue)" }
}
