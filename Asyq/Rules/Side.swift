/// How an asyk lies: the whole game hangs on it (docs/05-rules.md, §1).
enum Side: String, CaseIterable, Sendable {
    case alshy, taike, buk, shik, ompy, shonqai

    /// Регламент order alshy → taike → buk → shik, 1 is best. Ompy and shonqai stand outside
    /// the ranking.
    var rank: Int? {
        switch self {
        case .alshy: 1
        case .taike: 2
        case .buk: 3
        case .shik: 4
        case .ompy, .shonqai: nil
        }
    }

    /// The word the referee calls. Terms stay Kazakh in every language (docs/02-design.md).
    var term: String {
        switch self {
        case .alshy: "Алшы"
        case .taike: "Тәйке"
        case .buk: "Бүк"
        case .shik: "Шік"
        case .ompy: "Омпы"
        case .shonqai: "Шоңқай"
        }
    }
}
