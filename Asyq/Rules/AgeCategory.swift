/// «Бес табан» categories, which the game uses as difficulty levels
/// (Регламент, с. 62–69; docs/05-rules.md, §3).
enum AgeCategory: String, CaseIterable, Sendable {
    case bala, jasospirim, jigit, eresek

    var circleRadius: Float {
        switch self {
        case .bala: 1.5
        case .jasospirim: 2.0
        case .jigit, .eresek: 2.5
        }
    }

    /// From the throw line to the kon.
    var throwDistance: Float {
        switch self {
        case .bala: 3
        case .jasospirim: 4
        case .jigit: 5
        case .eresek: 6
        }
    }

    var konLength: Float {
        self == .bala ? 1.10 : 1.15
    }

    var keneiCount: Int {
        self == .eresek ? 15 : 13
    }

    /// The category's Kazakh name (docs/05-rules.md, §3).
    var term: String {
        switch self {
        case .bala: "Бала"
        case .jasospirim: "Жасөспірім"
        case .jigit: "Жігіт"
        case .eresek: "Ересек"
        }
    }

    /// The ages the Регламент made it for.
    var ages: String {
        switch self {
        case .bala: "7–10"
        case .jasospirim: "11–13"
        case .jigit: "14–16"
        case .eresek: "17+"
        }
    }

    /// Kenei to knock out first to win a partia.
    var winningCount: Int {
        self == .eresek ? 8 : 7
    }
}

/// Markings shared by every category.
enum FieldGeometry {
    /// Parallel lines either side of the kon (Регламент, с. 65).
    static let parallelLineOffset: Float = 0.15
    /// The throw line is as wide as the kon (Регламент, с. 65).
    static let throwLineHalfWidth: Float = 0.575
    /// docs/05-rules.md, question 6: our working width of the circle line.
    static let circleLineWidth: Float = 0.05
}
