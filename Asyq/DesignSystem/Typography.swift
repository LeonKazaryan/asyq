import SwiftUI

/// Type styles. SF Rounded covers every Kazakh letter (Ә Ғ Қ Ң Ө Ұ Ү Һ І), checked 2026-11-13.
enum Typography {
    /// The referee's calls: «ШЫҚТЫ!», «АЛШЫ!».
    static let call = Font.system(size: 56, weight: .black, design: .rounded)
    /// The number under a call: «+2».
    static let callDetail = Font.system(size: 30, weight: .heavy, design: .rounded)
    /// Small caps-like labels over the scene.
    static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let caption = Font.system(.footnote, design: .rounded).weight(.medium)
    /// Score digits.
    static let score = Font.system(.title2, design: .rounded).weight(.bold).monospacedDigit()
}
