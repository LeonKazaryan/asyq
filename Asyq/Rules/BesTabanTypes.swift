/// The vocabulary of a «Бес табан» match (docs/05-rules.md, §2–3). Pure values: the rules
/// engine and the arena talk to each other only through these.

/// The two sides of a match. Home throws from +z toward the kon, away from −z.
enum Player: Int, CaseIterable, Sendable, Hashable {
    case home, away

    var opponent: Player {
        self == .home ? .away : .home
    }
}

/// Which of the two allowed places a special throw comes from. For «Параллель» it is the
/// circle's wing at −x (`left`) or +x (`right`). For «Бес табан» it is five tabans along the
/// circle from the kenei: `left` turns counterclockwise seen from above, `right` clockwise.
enum Flank: Sendable, Hashable {
    case left, right

    var other: Flank {
        self == .left ? .right : .left
    }
}

/// Where the next throw comes from.
enum ThrowSpot: Equatable, Sendable {
    /// The thrower's own throw line.
    case line
    /// A series: the circle's edge on the axis, the thrower's side (п. 1.6).
    case circleEdge
    /// «Бес табан»: five tabans along the circle from the kenei (каз. п. 2.1).
    case besTaban(kenei: Int, flank: Flank)
    /// «Диагональ»: the far side of the circle, through the kon (п. 2.2).
    case diagonal(kenei: Int)
    /// «Параллель»: the circle's wing on the kon axis (п. 2.3).
    case parallel(kenei: Int, flank: Flank)

    /// The kenei a special throw is aimed at; nil for throws at the kon.
    var targetKenei: Int? {
        switch self {
        case .line, .circleEdge: nil
        case .besTaban(let kenei, _), .diagonal(let kenei), .parallel(let kenei, _): kenei
        }
    }
}

/// Where a kenei that moved but stayed in the circle lies, for the referee's commands.
enum KeneiZone: Sendable, Hashable {
    /// Between the parallel lines, within the kon's length: «Параллель».
    case parallel
    /// Within one taban of the circle line: «Бес табан».
    case nearCircle
    /// Anywhere else inside: «Диагональ».
    case middle
}

/// What the judge saw once a throw came to rest.
struct ThrowFacts: Equatable, Sendable {
    /// «Сырғытпа»: the saqa first touched the carpet outside the circle (п. 1.5.2).
    var isSlide = false
    /// Kenei wholly past the circle line.
    var knockedOut: [Int] = []
    /// Kenei the saqa itself touched, in the order it first touched them.
    var touched: [Int] = []
    /// Kenei that left their slot but stayed in the circle, and where they lie.
    var displaced: [Int: KeneiZone] = [:]
}

/// What the referee announces, in order.
enum RefereeCall: Hashable, Sendable {
    /// «Шықты!»: this many went out and count for the thrower.
    case out(Int)
    /// «Тимеді»: nothing out, the turn passes.
    case miss
    /// «Сырғытпа!»: the throw doesn't count, the turn passes.
    case slide
    case besTaban
    case diagonal
    case parallel
    case partiaWon(Player)
    case matchWon(Player)
}

/// What a throw changes on the field.
struct ThrowOutcome: Equatable, Sendable {
    var calls: [RefereeCall] = []
    /// Kenei counted and taken off the field.
    var removed: [Int] = []
    /// Kenei put back on their slots.
    var restored: [Int] = []
}
