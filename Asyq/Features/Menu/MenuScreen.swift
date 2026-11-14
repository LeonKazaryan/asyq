import SwiftUI

/// Until the real home screen (M8): pick a category, then a match against the rival or practice.
struct MenuScreen: View {
    @Binding var category: AgeCategory
    var onPlay: () -> Void
    var onPractice: () -> Void
    var onLesson: () -> Void
    var onRules: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.zenith.color, Palette.haze.color, Palette.felt.color.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    // The app's language is the system's per-app setting (Settings → Asyq).
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("Language", systemImage: "globe")
                            .font(Typography.label)
                            .foregroundStyle(Palette.ink.color)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .glassCapsule()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 24)
                VStack(spacing: 6) {
                    Text(verbatim: "Asyq")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.ink.color)
                    Text("Kazakh knucklebones")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundStyle(Palette.ink.color.opacity(0.55))
                }
                Spacer(minLength: 40)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: Term.besTaban.word)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                            if TermLanguage.current != .kazakh {
                                Text(verbatim: Term.besTaban.quotedGloss)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.ink.color.opacity(0.5))
                            }
                        }
                        Text("Federation rules: knock the bones out of the circle — first to \(category.winningCount) of \(category.keneiCount) wins the round")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ink.color.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.ink.color)
                    CategoryPicker(category: $category)
                    Button(action: onPlay) {
                        HStack {
                            Text("Play")
                            Text(verbatim: "· \(Names.rival)").opacity(0.6)
                        }
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Palette.paper.color)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.ink.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        SecondaryButton(title: Text("Practice"), systemImage: "scope", action: onPractice)
                        SecondaryButton(title: Text("How to play"), systemImage: "graduationcap", action: onLesson)
                        SecondaryButton(title: Text("Rules & words"), systemImage: "book", action: onRules)
                    }
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

/// A quiet tile under the main button.
private struct SecondaryButton: View {
    let title: Text
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                title
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Palette.ink.color)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Palette.ink.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The four categories of the Регламент, as difficulty: distance and circle grow with age.
private struct CategoryPicker: View {
    @Binding var category: AgeCategory

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AgeCategory.allCases, id: \.self) { option in
                Button {
                    category = option
                } label: {
                    VStack(spacing: 2) {
                        Text(option.name)
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(Measurement(value: Double(option.throwDistance), unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided))
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .opacity(0.6)
                    }
                    .foregroundStyle(option == category ? Palette.paper.color : Palette.ink.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(option == category ? Palette.felt.color : Palette.ink.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(String(localized: option.name)), ages \(option.ages)"))
                .accessibilityAddTraits(option == category ? .isSelected : [])
            }
        }
        .animation(Motion.snappy, value: category)
    }
}
