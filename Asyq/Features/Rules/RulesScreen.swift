import SwiftUI

/// The game's manual: the bones, the field, how a turn goes, who starts, the referee's calls,
/// and every Kazakh word with what it means. A reading screen: calm, airy, system text sizes;
/// the diagrams do most of the explaining.
struct RulesScreen: View {
    @State private var shown: AgeCategory
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onClose: () -> Void

    init(category: AgeCategory, onClose: @escaping () -> Void) {
        _shown = State(initialValue: category)
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Palette.zenith.color, Palette.haze.color, Palette.felt.color.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    hero.appearing(0, appeared, reduceMotion)
                    RulesSection(title: "The bones") { BonesCard() }
                        .appearing(1, appeared, reduceMotion)
                    RulesSection(title: "The field") { FieldCard(category: $shown) }
                        .appearing(2, appeared, reduceMotion)
                    RulesSection(title: "How a turn goes") { TurnCard(category: shown) }
                        .revealing(reduceMotion)
                    RulesSection(title: "Who starts") { IiruCard() }
                        .revealing(reduceMotion)
                    RulesSection(title: "The referee's calls") { CommandsCard(category: shown) }
                        .revealing(reduceMotion)
                    RulesSection(title: "Words") { GlossaryCard() }
                        .revealing(reduceMotion)
                    Text("The rules follow the regulation of the Kazakhstan Asyq Atu Federation, 2011–2022.")
                        .font(RulesFont.small)
                        .foregroundStyle(Palette.ink.color.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 68)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            // Text scrolls away softly under the back button instead of colliding with it.
            LinearGradient(colors: [Palette.zenith.color, Palette.zenith.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            GlassIconButton(systemName: "chevron.left", label: "Back", action: onClose)
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .onAppear { appeared = true }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                RulesBoneGlyph(kind: .saqa)
                ForEach(0..<3, id: \.self) { _ in RulesBoneGlyph(kind: .kenei) }
            }
            .padding(.bottom, 10)
            Text("Rules & words")
                .font(RulesFont.eyebrow)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Palette.ink.color.opacity(0.5))
            Text(verbatim: Term.asyqAtu.word)
                .font(.system(.largeTitle, design: .rounded).weight(.black))
                .foregroundStyle(Palette.ink.color)
            Text(Term.asyqAtu.gloss)
                .font(RulesFont.headline)
                .italic()
                .foregroundStyle(Palette.ink.color.opacity(0.65))
            Text(Term.asyqAtu.explanation)
                .font(RulesFont.body)
                .foregroundStyle(Palette.ink.color.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Sections

/// The bones: your saqa and the kenei you knock out.
private struct BonesCard: View {
    var body: some View {
        RulesCard {
            VStack(alignment: .leading, spacing: 18) {
                row(.saqa, glyph: .saqa, note: Text("A saqa weighs 28–30 g, a kenei 15–17 g: the heavier bone does the knocking."))
                Divider()
                row(.kenei, glyph: .kenei, note: nil)
            }
        }
    }

    private func row(_ term: Term, glyph: RulesBoneGlyph.Kind, note: Text?) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RulesBoneGlyph(kind: glyph)
                .frame(width: 50, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                TermTitle(term: term)
                Text(term.explanation)
                    .font(RulesFont.body)
                    .foregroundStyle(Palette.ink.color.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    note
                        .font(RulesFont.small)
                        .foregroundStyle(Palette.ink.color.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The field to scale, the kon up close, and the four categories to compare.
private struct FieldCard: View {
    @Binding var category: AgeCategory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RulesCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                RulesFieldDiagram(category: category)
                    .frame(height: 340)
                    .animation(reduceMotion ? nil : Motion.smooth, value: category)
                RulesKonCloseUp(category: category)
                    .frame(height: 80)
                RulesCategorySwitcher(selection: $category)
                Text("Younger players have a smaller circle, a shorter throw and 13 kenei instead of 15.")
                    .font(RulesFont.small)
                    .foregroundStyle(Palette.ink.color.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
    }
}

/// What happens after a throw, in four lines.
private struct TurnCard: View {
    let category: AgeCategory

    var body: some View {
        RulesCard {
            VStack(alignment: .leading, spacing: 18) {
                TurnRow(symbol: "arrow.up.forward", term: .shyqty)
                TurnRow(symbol: "arrow.uturn.backward", term: .timedi)
                TurnRow(symbol: "exclamationmark.triangle", term: .syrgytpa)
                HStack(alignment: .top, spacing: 14) {
                    RulesIcon(symbol: "flag.checkered")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First to \(category.winningCount) of \(category.keneiCount)")
                            .font(RulesFont.headline)
                            .foregroundStyle(Palette.ink.color)
                        Text("Knock out \(category.winningCount) of the \(category.keneiCount) kenei first to win the round. Win two rounds to win the match.")
                            .font(RulesFont.body)
                            .foregroundStyle(Palette.ink.color.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct TurnRow: View {
    let symbol: String
    let term: Term

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RulesIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(term.call)
                        .font(RulesFont.headline)
                        .foregroundStyle(Palette.ink.color)
                    Text(verbatim: term.word)
                        .font(RulesFont.small.italic())
                        .foregroundStyle(Palette.ink.color.opacity(0.5))
                }
                Text(term.explanation)
                    .font(RulesFont.body)
                    .foregroundStyle(Palette.ink.color.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Иіру and the ranking of the sides.
private struct IiruCard: View {
    private let ranked: [Side] = [.alshy, .taike, .buk, .shik]

    var body: some View {
        RulesCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    TermTitle(term: .iiru)
                    Text(Term.iiru.explanation)
                        .font(RulesFont.body)
                        .foregroundStyle(Palette.ink.color.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("From the best side to the lowest:")
                    .font(RulesFont.small)
                    .foregroundStyle(Palette.ink.color.opacity(0.55))
                VStack(spacing: 10) {
                    ForEach(ranked, id: \.self) { side in
                        SideRow(side: side)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    HStack(spacing: -6) {
                        RulesSidePictogram(side: .ompy)
                        RulesSidePictogram(side: .shonqai)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(Term.ompy.word) · \(Term.shonqai.word)")
                            .font(RulesFont.headline)
                            .foregroundStyle(Palette.ink.color)
                        Text("Standing on an end: no rank, spin again.")
                            .font(RulesFont.small)
                            .foregroundStyle(Palette.ink.color.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct SideRow: View {
    let side: Side

    var body: some View {
        HStack(spacing: 12) {
            RulesSidePictogram(side: side)
            VStack(alignment: .leading, spacing: 2) {
                SideLabel(side: side)
                    .font(RulesFont.headline)
                Text(Term(side).gloss)
                    .font(RulesFont.small)
                    .foregroundStyle(Palette.ink.color.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The three commands, each with its diagram.
private struct CommandsCard: View {
    let category: AgeCategory

    var body: some View {
        RulesCard {
            VStack(alignment: .leading, spacing: 22) {
                Text("When your saqa hits a kenei that stays inside the circle, the referee may give you one more throw at it:")
                    .font(RulesFont.body)
                    .foregroundStyle(Palette.ink.color.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                CommandRow(command: .besTaban, term: .besTaban, category: category)
                Divider()
                CommandRow(command: .diagonal, term: .diagonal, category: category)
                Divider()
                CommandRow(command: .parallel, term: .parallel, category: category)
            }
        }
    }
}

private struct CommandRow: View {
    let command: RefereeCall
    let term: Term
    let category: AgeCategory
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            CommandDiagram(command: command, category: category)
                .frame(width: typeSize.isAccessibilitySize ? 200 : 112)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: term.word)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink.color)
                Text(term.name)
                    .font(RulesFont.small.weight(.semibold))
                    .foregroundStyle(Palette.ink.color.opacity(0.55))
                Text(term.explanation)
                    .font(RulesFont.body)
                    .foregroundStyle(Palette.ink.color.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

/// Every word, grouped.
private struct GlossaryCard: View {
    private let groups: [(title: LocalizedStringKey, terms: [Term])] = [
        ("The referee's calls", [.shyqty, .timedi, .syrgytpa, .besTaban, .diagonal, .parallel]),
        ("The match", [.iiru, .kezek, .zhenis, .zhenilis]),
        ("Bones and field", [.asyqAtu, .saqa, .kenei, .kon]),
        ("The sides", [.alshy, .taike, .buk, .shik, .ompy, .shonqai]),
        ("The throw", [.tartTaZhiber]),
    ]

    var body: some View {
        RulesCard {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(groups[index].title)
                            .font(RulesFont.eyebrow)
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.ink.color.opacity(0.45))
                        ForEach(groups[index].terms, id: \.self) { term in
                            GlossaryRow(term: term)
                        }
                    }
                }
            }
        }
    }
}

private struct GlossaryRow: View {
    let term: Term

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: term.word)
                    .font(RulesFont.headline)
                    .foregroundStyle(Palette.ink.color)
                // Latin readers also see how it's written in Kazakh.
                if term.kazakh != term.word {
                    Text(verbatim: term.kazakh)
                        .font(RulesFont.small)
                        .foregroundStyle(Palette.ink.color.opacity(0.45))
                }
            }
            Text(term.gloss)
                .font(RulesFont.small.italic())
                .foregroundStyle(Palette.ink.color.opacity(0.65))
            Text(term.explanation)
                .font(RulesFont.small)
                .foregroundStyle(Palette.ink.color.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// Type for a reading screen: system text styles, so Dynamic Type scales everything.
private enum RulesFont {
    static let eyebrow = Font.system(.caption, design: .rounded).weight(.heavy)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.subheadline, design: .rounded)
    static let small = Font.system(.footnote, design: .rounded)
}

/// A section's quiet title over its card.
private struct RulesSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink.color)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct RulesCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// A term as a small title: the word, then what it means.
private struct TermTitle: View {
    let term: Term

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: term.word)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink.color)
            Text(term.gloss)
                .font(RulesFont.small.italic())
                .foregroundStyle(Palette.ink.color.opacity(0.55))
        }
    }
}

private struct RulesIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.paper.color)
            .frame(width: 34, height: 34)
            .background(Palette.felt.color, in: Circle())
            .accessibilityHidden(true)
    }
}

private extension View {
    /// The first sections settle in one after another when the screen opens.
    func appearing(_ index: Int, _ appeared: Bool, _ reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 18)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.smooth.delay(Double(index) * 0.07), value: appeared)
    }

    /// Further down, each section rises gently into view as it scrolls in.
    func revealing(_ reduceMotion: Bool) -> some View {
        scrollTransition(.animated(Motion.smooth).threshold(.visible(0.12))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.35)
                .offset(y: reduceMotion ? 0 : phase.value * 16)
        }
    }
}

#Preview {
    RulesScreen(category: .eresek, onClose: {})
}
