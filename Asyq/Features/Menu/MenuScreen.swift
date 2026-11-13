import SwiftUI

/// Until the real home screen (M8): pick a category, then a match against the rival or practice.
struct MenuScreen: View {
    @Binding var category: AgeCategory
    var onPlay: () -> Void
    var onPractice: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.zenith.color, Palette.haze.color, Palette.felt.color.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 40)
                VStack(spacing: 6) {
                    Text(verbatim: "Asyq")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.ink.color)
                    Text(verbatim: "асық ату")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundStyle(Palette.ink.color.opacity(0.55))
                }
                Spacer(minLength: 40)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Бес табан")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        Text("Federation rules: knock kenei out of the circle, first to \(category.winningCount) wins the partia")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ink.color.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.ink.color)
                    CategoryPicker(category: $category)
                    Button(action: onPlay) {
                        HStack {
                            Text("Play")
                            Text(verbatim: "· Нұрлан").opacity(0.6)
                        }
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Palette.paper.color)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.ink.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button(action: onPractice) {
                        Text("Practice")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Palette.ink.color)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
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
                        Text(verbatim: option.term)
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
                .accessibilityLabel(Text(verbatim: "\(option.term), \(option.ages)"))
                .accessibilityAddTraits(option == category ? .isSelected : [])
            }
        }
        .animation(Motion.snappy, value: category)
    }
}
