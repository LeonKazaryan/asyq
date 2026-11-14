import SwiftUI

/// A side's rank as dots: four for alshy down to one for shik, none for the unranked ends.
/// Reads without any words.
struct RankPips: View {
    let side: Side
    var color: Color = Palette.ink.color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < filled ? color : color.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private var filled: Int {
        side.rank.map { 5 - $0 } ?? 0
    }
}

/// A side of the asyq: its rank dots and its word.
struct SideLabel: View {
    let side: Side
    var color: Color = Palette.ink.color

    var body: some View {
        HStack(spacing: 6) {
            RankPips(side: side, color: color)
            Text(verbatim: Term(side).word)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Term(side).word))
        .accessibilityValue(side.rank.map { Text("Rank \($0) of 4") } ?? Text("No rank"))
    }
}
