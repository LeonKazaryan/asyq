import SwiftUI

/// The field from above, to scale: the circle, the kon, both throw lines, who stands where.
/// The adults' field sets the scale, so switching to a younger category visibly shrinks it.
/// Animatable: the circle and the throw lines glide between categories.
struct RulesFieldDiagram: View, Animatable {
    var circleRadius: Double
    var throwDistance: Double
    var konLength: Double
    var keneiCount: Int

    init(category: AgeCategory) {
        circleRadius = Double(category.circleRadius)
        throwDistance = Double(category.throwDistance)
        konLength = Double(category.konLength)
        keneiCount = category.keneiCount
    }

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(circleRadius, throwDistance), konLength) }
        set {
            circleRadius = newValue.first.first
            throwDistance = newValue.first.second
            konLength = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Diagram of the field seen from above: a circle with the kon of kenei across its middle, and a throw line on each side."))
        .accessibilityValue(Text("Circle \(diameterText), throw from \(distanceText)"))
    }

    private var diameterText: Text {
        Text(Measurement(value: circleRadius * 2, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    private var distanceText: Text {
        Text(Measurement(value: throwDistance, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let largest = Double(AgeCategory.eresek.throwDistance) + 0.75
        let scale = (size.height - 24) / (2 * largest)
        // Left of center: the labels live on the right.
        let center = CGPoint(x: size.width * 0.4, y: size.height / 2)
        func point(_ x: Double, _ z: Double) -> CGPoint {
            CGPoint(x: center.x + x * scale, y: center.y + z * scale)
        }
        let thread = Palette.thread.color
        let paper = Palette.paper.color

        context.fill(
            Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 22, style: .continuous),
            with: .linearGradient(
                Gradient(colors: [Palette.felt.color.opacity(0.86), Palette.felt.color]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // The throw axis, faint, from line to line.
        var axis = Path()
        axis.move(to: point(0, -throwDistance))
        axis.addLine(to: point(0, throwDistance))
        context.stroke(axis, with: .color(thread.opacity(0.22)), style: StrokeStyle(lineWidth: 0.7, dash: [2, 4]))

        let r = circleRadius * scale
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
            with: .color(thread),
            style: StrokeStyle(lineWidth: 2, dash: [6, 2.5])
        )

        let half = konLength / 2
        let band = max(Double(FieldGeometry.parallelLineOffset), 3.5 / scale)
        for offset in [-band, band] {
            var line = Path()
            line.move(to: point(-half, offset))
            line.addLine(to: point(half, offset))
            context.stroke(line, with: .color(thread.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 1.8]))
        }
        let row = CGRect(x: point(-half, 0).x, y: center.y - 2, width: konLength * scale, height: 4)
        context.fill(Path(roundedRect: row, cornerRadius: 2), with: .color(Palette.bone.color))

        let throwHalf = Double(FieldGeometry.throwLineHalfWidth)
        for z in [throwDistance, -throwDistance] {
            var line = Path()
            line.move(to: point(-throwHalf, z))
            line.addLine(to: point(throwHalf, z))
            context.stroke(line, with: .color(thread), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Who stands where: you below, the rival above.
        let you = point(0, throwDistance + 0.42)
        let rival = point(0, -throwDistance - 0.42)
        for (at, color) in [(you, Palette.saqa.color), (rival, Palette.rivalSaqa.color)] {
            let disk = Path(ellipseIn: CGRect(x: at.x - 5, y: at.y - 5, width: 10, height: 10))
            context.fill(disk, with: .color(color))
            context.stroke(disk, with: .color(paper), lineWidth: 1.5)
        }

        // Labels on the right, joined to what they name.
        let labelX = center.x + Double(AgeCategory.eresek.circleRadius) * scale + 14
        func label(_ text: Text, at y: Double, from anchor: CGPoint) {
            var leader = Path()
            leader.move(to: anchor)
            leader.addLine(to: CGPoint(x: labelX - 5, y: y))
            context.stroke(leader, with: .color(paper.opacity(0.55)), lineWidth: 0.75)
            context.fill(Path(ellipseIn: CGRect(x: anchor.x - 1.8, y: anchor.y - 1.8, width: 3.6, height: 3.6)), with: .color(paper))
            let resolved = context.resolve(text.font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(paper))
            context.draw(resolved, at: CGPoint(x: labelX, y: y), anchor: .leading)
        }
        label(Text(verbatim: Term.kon.word), at: center.y + 22, from: point(half, 0))
        let circleAnchor = CGPoint(x: center.x + r * cos(0.75), y: center.y - r * sin(0.75))
        label(Text("Circle \(diameterText)"), at: min(circleAnchor.y, center.y - 26), from: circleAnchor)
        label(Text("Throw line"), at: point(0, throwDistance).y, from: point(throwHalf, throwDistance))
        label(Text("You"), at: you.y + 14, from: CGPoint(x: you.x + 5, y: you.y))
        label(Text("Rival"), at: rival.y - 14, from: CGPoint(x: rival.x + 5, y: rival.y))

        // The distance, as a dimension line on the left: from your line to the kon.
        let dimensionX = center.x - Double(AgeCategory.eresek.circleRadius) * scale - 18
        var dimension = Path()
        dimension.move(to: CGPoint(x: dimensionX, y: center.y))
        dimension.addLine(to: CGPoint(x: dimensionX, y: point(0, throwDistance).y))
        for y in [center.y, point(0, throwDistance).y] {
            dimension.move(to: CGPoint(x: dimensionX - 4, y: y))
            dimension.addLine(to: CGPoint(x: dimensionX + 4, y: y))
        }
        context.stroke(dimension, with: .color(paper.opacity(0.8)), lineWidth: 1)
        let distance = context.resolve(distanceText.font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(paper))
        context.draw(distance, at: CGPoint(x: dimensionX - 7, y: center.y + throwDistance * scale / 2), anchor: .trailing)
    }
}

/// The kon up close: the kenei standing in their row, one saqa apart, and the parallel lines
/// 15 cm either side. Too small to see on the whole field.
struct RulesKonCloseUp: View {
    let category: AgeCategory

    var body: some View {
        Canvas { context, size in
            let thread = Palette.thread.color
            let paper = Palette.paper.color
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18, style: .continuous),
                with: .color(Palette.felt.color)
            )
            let middle = size.height / 2 - 6
            let inset = 18.0
            let bandOffset = 17.0
            for offset in [-bandOffset, bandOffset] {
                var line = Path()
                line.move(to: CGPoint(x: inset, y: middle + offset))
                line.addLine(to: CGPoint(x: size.width - inset - 52, y: middle + offset))
                context.stroke(line, with: .color(thread.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            }
            var kon = Path()
            kon.move(to: CGPoint(x: inset, y: middle))
            kon.addLine(to: CGPoint(x: size.width - inset - 52, y: middle))
            context.stroke(kon, with: .color(thread.opacity(0.85)), lineWidth: 1.2)

            let count = category.keneiCount
            let rowWidth = size.width - 2 * inset - 52
            let spacing = rowWidth / Double(count)
            let width = min(spacing * 0.55, 12)
            for index in 0..<count {
                let x = inset + spacing * (Double(index) + 0.5)
                let body = CGRect(x: x - width / 2, y: middle - width * 0.42, width: width, height: width * 0.84)
                context.fill(Path(roundedRect: body, cornerRadius: width * 0.28, style: .continuous), with: .color(Palette.bone.color))
                context.stroke(Path(roundedRect: body, cornerRadius: width * 0.28, style: .continuous), with: .color(Palette.ink.color.opacity(0.2)), lineWidth: 0.5)
            }

            // 15 cm, measured between the kon and the upper line.
            let dimensionX = size.width - inset - 40
            var dimension = Path()
            dimension.move(to: CGPoint(x: dimensionX, y: middle))
            dimension.addLine(to: CGPoint(x: dimensionX, y: middle - bandOffset))
            for y in [middle, middle - bandOffset] {
                dimension.move(to: CGPoint(x: dimensionX - 3, y: y))
                dimension.addLine(to: CGPoint(x: dimensionX + 3, y: y))
            }
            context.stroke(dimension, with: .color(paper.opacity(0.85)), lineWidth: 1)
            let offsetText = context.resolve(
                Text(Measurement(value: (Double(FieldGeometry.parallelLineOffset) * 100).rounded(), unit: UnitLength.centimeters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(paper)
            )
            context.draw(offsetText, at: CGPoint(x: dimensionX + 6, y: middle - bandOffset / 2), anchor: .leading)

            let caption = context.resolve(
                Text("\(Text(verbatim: Term.kon.word)) · \(category.keneiCount) kenei · \(Text(Measurement(value: (Double(category.konLength) * 100).rounded(), unit: UnitLength.centimeters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))))")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(paper.opacity(0.9))
            )
            context.draw(caption, at: CGPoint(x: inset, y: size.height - 9), anchor: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The kon up close: \(category.keneiCount) kenei standing in a row, one saqa apart, with a dashed line 15 centimeters away on each side."))
    }
}

/// The four categories of the Регламент by age and distance, as language-free as possible.
struct RulesCategorySwitcher: View {
    @Binding var selection: AgeCategory

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AgeCategory.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 1) {
                        Text(verbatim: option.ages)
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                        Text(Measurement(value: Double(option.throwDistance), unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided))
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .opacity(0.65)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(option == selection ? Palette.paper.color : Palette.ink.color)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        option == selection ? Palette.felt.color : Palette.ink.color.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Ages \(option.ages)"))
                .accessibilityValue(Text(Measurement(value: Double(option.throwDistance), unit: UnitLength.meters), format: .measurement(width: .wide, usage: .asProvided)))
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .animation(Motion.snappy, value: selection)
    }
}

#Preview {
    VStack(spacing: 12) {
        RulesFieldDiagram(category: .eresek).frame(height: 340)
        RulesKonCloseUp(category: .eresek).frame(height: 78)
    }
    .padding()
}
