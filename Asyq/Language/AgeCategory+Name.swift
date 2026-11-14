import Foundation

extension AgeCategory {
    /// The category's name in the player's language; `term` is the Kazakh one.
    var name: LocalizedStringResource {
        switch self {
        case .bala: "Kids"
        case .jasospirim: "Juniors"
        case .jigit: "Youth"
        case .eresek: "Adults"
        }
    }
}
