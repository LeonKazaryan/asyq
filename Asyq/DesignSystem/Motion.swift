import SwiftUI

/// Animation tokens (docs/02-design.md). Feature code uses these, never raw values.
enum Motion {
    /// Toggles, hints, small state changes.
    static let snappy = Animation.spring(duration: 0.3, bounce: 0.15)
    /// Things popping in: the score, the referee's call.
    static let bouncy = Animation.spring(duration: 0.5, bounce: 0.35)
    /// Large moves without overshoot.
    static let smooth = Animation.spring(duration: 0.6, bounce: 0)
    /// A call slammed onto the screen: fast, one small rebound.
    static let slam = Animation.spring(duration: 0.34, bounce: 0.3)
    /// Celebrations.
    static let celebrate = Animation.spring(duration: 0.7, bounce: 0.5)
}
