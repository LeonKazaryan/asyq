import Foundation

/// A word of the game that stays Kazakh in every language (docs/02-design.md, «Обучение»):
/// «шықты» is to asyq atu what «ippon» is to judo. A player who doesn't know it sees what it
/// means first, with the word beside it; after a few times the word takes over
/// (`TermFamiliarity`).
enum Term: String, CaseIterable, Sendable {
    // The referee's calls.
    case shyqty, timedi, syrgytpa, besTaban, diagonal, parallel
    // The match.
    case iiru, kezek, zhenis, zhenilis
    // The bones and the field.
    case asyqAtu, saqa, kenei, kon
    // The sides of an asyq.
    case alshy, taike, buk, shik, ompy, shonqai
    // The throw.
    case tartTaZhiber

    /// As written in Kazakh.
    var kazakh: String {
        switch self {
        case .shyqty: "Шықты"
        case .timedi: "Тимеді"
        case .syrgytpa: "Сырғытпа"
        case .besTaban: "Бес табан"
        case .diagonal: "Диагональ"
        case .parallel: "Параллель"
        case .iiru: "Иіру"
        case .kezek: "Кезек"
        case .zhenis: "Жеңіс"
        case .zhenilis: "Жеңіліс"
        case .asyqAtu: "Асық ату"
        case .saqa: "Сақа"
        case .kenei: "Кеней"
        case .kon: "Көн"
        case .alshy: "Алшы"
        case .taike: "Тәйке"
        case .buk: "Бүк"
        case .shik: "Шік"
        case .ompy: "Омпы"
        case .shonqai: "Шоңқай"
        case .tartTaZhiber: "Тарт та жібер"
        }
    }

    /// For readers of Latin script: an English-friendly spelling, the way the words are
    /// usually written for visitors (zh for ж, q for қ, sh for ш), not the 2021 alphabet.
    var latin: String {
        switch self {
        case .shyqty: "Shyqty"
        case .timedi: "Timedi"
        case .syrgytpa: "Syrgytpa"
        case .besTaban: "Bes taban"
        case .diagonal: "Diagonal"
        case .parallel: "Parallel"
        case .iiru: "Iiru"
        case .kezek: "Kezek"
        case .zhenis: "Zhenis"
        case .zhenilis: "Zhenilis"
        case .asyqAtu: "Asyq atu"
        case .saqa: "Saqa"
        case .kenei: "Kenei"
        case .kon: "Kon"
        case .alshy: "Alshy"
        case .taike: "Taike"
        case .buk: "Buk"
        case .shik: "Shik"
        case .ompy: "Ompy"
        case .shonqai: "Shonqai"
        case .tartTaZhiber: "Tart ta zhiber"
        }
    }

    /// What the referee's call means, as a headline in the player's language.
    var call: LocalizedStringResource {
        switch self {
        case .shyqty: "Out!"
        case .timedi: "Miss"
        case .syrgytpa: "Slid in!"
        case .besTaban: "Five feet!"
        case .diagonal: "Diagonal!"
        case .parallel: "Parallel!"
        case .iiru: "Who starts?"
        case .kezek: "Turn"
        case .zhenis: "Victory!"
        case .zhenilis: "Defeat"
        case .asyqAtu: "Knucklebone shooting"
        case .saqa: "Shooter"
        case .kenei: "Target bone"
        case .kon: "Target line"
        case .alshy: "Alshy"
        case .taike: "Taike"
        case .buk: "Buk"
        case .shik: "Shik"
        case .ompy: "Ompy"
        case .shonqai: "Shonqai"
        case .tartTaZhiber: "Pull back and let go"
        }
    }

    /// The word's own meaning, translated: «шықты» is “it's out”.
    var gloss: LocalizedStringResource {
        switch self {
        case .shyqty: "it's out"
        case .timedi: "no hit"
        case .syrgytpa: "don't slide it"
        case .besTaban: "five feet"
        case .diagonal: "diagonal"
        case .parallel: "parallel"
        case .iiru: "the spin"
        case .kezek: "turn"
        case .zhenis: "victory"
        case .zhenilis: "defeat"
        case .asyqAtu: "shooting the asyqs"
        case .saqa: "the shooter bone"
        case .kenei: "a target bone"
        case .kon: "the line of target bones"
        case .alshy: "on its side, hollow up"
        case .taike: "on its other side"
        case .buk: "back up"
        case .shik: "hollow up"
        case .ompy: "standing on its end"
        case .shonqai: "standing on its other end"
        case .tartTaZhiber: "pull and let go"
        }
    }

    /// One or two sentences for the rules and the tips.
    var explanation: LocalizedStringResource {
        switch self {
        case .shyqty: "A kenei crossed the circle line: it's yours, and you throw again, closer, from the circle's edge."
        case .timedi: "Nothing went out of the circle. The kenei go back onto the kon and the turn passes."
        case .syrgytpa: "Your saqa touched the carpet before the circle and slid in. The throw doesn't count."
        case .besTaban: "Your saqa hit a kenei that stayed just inside the circle line. Measure five feet along the circle and throw at it again."
        case .diagonal: "Your saqa hit a kenei that stayed between the kon and the circle. Throw at it again from the far side, across the kon."
        case .parallel: "Your saqa hit a kenei that stayed between the parallel lines. Throw at it again from the circle's wing."
        case .iiru: "Before a match both players spin their saqa onto the carpet. Whoever lands the higher side throws first."
        case .kezek: "Whose throw it is."
        case .zhenis: "You won the match."
        case .zhenilis: "Your rival won the match."
        case .asyqAtu: "The Kazakh national game of throwing a bone at bones, on UNESCO's list of intangible heritage since 2017."
        case .saqa: "Your shooter: the biggest, heaviest asyq. You throw it at the kenei."
        case .kenei: "The asyqs standing in a row in the middle of the circle. Knock them out of it."
        case .kon: "The short line in the middle of the circle where the kenei stand, with a parallel line on each side."
        case .alshy: "Lies on a narrow side. The best side there is."
        case .taike: "Lies on the other narrow side. Second best."
        case .buk: "Lies on its rounded back. Third."
        case .shik: "Lies on its hollow back, the hollow up. The lowest."
        case .ompy: "Stands upright on one end. Rare, and outside the ranking."
        case .shonqai: "Stands upright on the other end. Rare, and outside the ranking."
        case .tartTaZhiber: "Pull down for power, sideways to aim, then let go."
        }
    }

    /// The side of a bone as a term.
    init(_ side: Side) {
        switch side {
        case .alshy: self = .alshy
        case .taike: self = .taike
        case .buk: self = .buk
        case .shik: self = .shik
        case .ompy: self = .ompy
        case .shonqai: self = .shonqai
        }
    }
}

/// How this player reads Kazakh words: in Kazakh, Russian or any other language.
enum TermLanguage {
    case kazakh
    /// Russian readers read Cyrillic, so the Kazakh word as written.
    case cyrillic
    /// Everyone else: the Latin spelling.
    case latin

    /// The app's language as chosen by the system (per-app language in Settings).
    static var current: TermLanguage {
        switch Bundle.main.preferredLocalizations.first?.prefix(2) {
        case "kk": .kazakh
        case "ru": .cyrillic
        default: .latin
        }
    }
}

extension Term {
    /// The word as this player reads it.
    var word: String {
        TermLanguage.current == .latin ? latin : kazakh
    }

    /// A short name for a label: the word once known, its meaning before.
    var label: String {
        TermFamiliarity.isLearned(self) ? word : String(localized: name)
    }

    /// The gloss in quotes, the way this language quotes: “it's out”, «вылетел».
    var quotedGloss: String {
        let gloss = String(localized: gloss)
        return String(localized: "“\(gloss)”")
    }

    /// The meaning as a plain name, not shouted: «Five feet».
    var name: LocalizedStringResource {
        switch self {
        case .besTaban: "Five feet"
        case .diagonal: "Diagonal"
        case .parallel: "Parallel"
        default: call
        }
    }
}

/// Names of people, written the way this player reads: a name, not a word to translate.
enum Names {
    static var rival: String {
        TermLanguage.current == .latin ? "Nurlan" : "Нұрлан"
    }
}
