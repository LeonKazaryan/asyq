import SwiftUI

/// A bone as the game draws it for now: a rounded "pebble" (ADR-009), lit from above. The
/// saqa painted and bigger, a kenei bone-white. Replace with the scans' silhouettes later.
struct RulesBoneGlyph: View {
    enum Kind {
        case saqa, kenei
    }

    let kind: Kind

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: kind == .saqa ? 11 : 8, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: kind == .saqa
                        ? [Palette.saqa.color.opacity(0.82), Palette.saqa.color]
                        : [Palette.bone.color, Palette.bone.color.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                // A soft highlight along the top edge: it reads as a solid thing, not a sticker.
                Capsule()
                    .fill(Color.white.opacity(kind == .saqa ? 0.28 : 0.6))
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
            }
            .overlay(shape.stroke(Palette.ink.color.opacity(0.14), lineWidth: 0.75))
            .frame(width: kind == .saqa ? 46 : 34, height: kind == .saqa ? 32 : 24)
            .shadow(color: Palette.ink.color.opacity(0.18), radius: 4, y: 3)
            .accessibilityHidden(true)
    }
}

/// How a bone lies on each side, in profile on the carpet: which face is up is marked — a
/// dimple for shik's hollow, a bump for buk's back, a groove on the narrow sides, standing
/// tall on its ends for ompy and shonqai.
struct RulesSidePictogram: View {
    let side: Side

    var body: some View {
        Canvas { context, size in
            let ink = Palette.ink.color
            let ground = size.height - 3
            var floor = Path()
            floor.move(to: CGPoint(x: 2, y: ground))
            floor.addLine(to: CGPoint(x: size.width - 2, y: ground))
            context.stroke(floor, with: .color(ink.opacity(0.22)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            let (width, height): (Double, Double) = switch side {
            case .buk, .shik: (34, 13)
            case .alshy, .taike: (30, 19)
            case .ompy, .shonqai: (15, 27)
            }
            let body = CGRect(x: (size.width - width) / 2, y: ground - height - 0.5, width: width, height: height)
            let outline = Path(roundedRect: body, cornerRadius: min(width, height) * 0.32, style: .continuous)
            context.fill(outline, with: .linearGradient(
                Gradient(colors: [Palette.bone.color, Palette.bone.color.opacity(0.8)]),
                startPoint: CGPoint(x: 0, y: body.minY),
                endPoint: CGPoint(x: 0, y: body.maxY)
            ))
            context.stroke(outline, with: .color(ink.opacity(0.45)), lineWidth: 1)

            let mark = ink.opacity(0.6)
            switch side {
            case .buk:
                // The rounded back, up.
                var bump = Path()
                bump.move(to: CGPoint(x: body.midX - 9, y: body.minY + 1))
                bump.addQuadCurve(to: CGPoint(x: body.midX + 9, y: body.minY + 1), control: CGPoint(x: body.midX, y: body.minY - 6))
                context.stroke(bump, with: .color(mark), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case .shik:
                // The hollow, up.
                let dimple = CGRect(x: body.midX - 7, y: body.minY + 1.5, width: 14, height: 5)
                context.fill(Path(ellipseIn: dimple), with: .color(ink.opacity(0.3)))
            case .alshy:
                var groove = Path()
                groove.move(to: CGPoint(x: body.midX - 7, y: body.minY + 4))
                groove.addCurve(to: CGPoint(x: body.midX + 7, y: body.minY + 4), control1: CGPoint(x: body.midX - 2, y: body.minY + 9), control2: CGPoint(x: body.midX + 2, y: body.minY - 1))
                context.stroke(groove, with: .color(mark), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case .taike:
                var ridge = Path()
                ridge.move(to: CGPoint(x: body.midX - 7, y: body.minY + 4))
                ridge.addLine(to: CGPoint(x: body.midX + 7, y: body.minY + 4))
                context.stroke(ridge, with: .color(mark), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case .ompy, .shonqai:
                // The end it stands on: «whiskers» down for ompy, up for shonqai.
                let y = side == .ompy ? body.maxY - 4 : body.minY + 4
                var whiskers = Path()
                whiskers.move(to: CGPoint(x: body.midX - 3.5, y: y))
                whiskers.addLine(to: CGPoint(x: body.midX + 3.5, y: y))
                context.stroke(whiskers, with: .color(mark), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .frame(width: 44, height: 34)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(Side.allCases, id: \.self) { RulesSidePictogram(side: $0) }
    }
    .padding()
}
