import SwiftUI

/// A top-down sketch of one referee command, like the Регламент's diagrams (каз. с. 24–25,
/// docs/05-rules.md §3): the circle, the kon with its parallel lines, the fallen kenei
/// glowing, where the thrower stands and the arrow of the throw. The home player throws from
/// the bottom. Square; it takes the width it's offered.
struct CommandDiagram: View {
    /// Only `.besTaban`, `.diagonal` and `.parallel` are drawn; anything else draws the bare field.
    let command: RefereeCall
    var category: AgeCategory = .eresek

    var body: some View {
        Canvas { context, size in
            let sketch = Sketch(size: size, category: category)
            sketch.drawField(in: &context)
            switch command {
            case .besTaban: sketch.drawBesTaban(in: &context)
            case .diagonal: sketch.drawDiagonal(in: &context)
            case .parallel: sketch.drawParallel(in: &context)
            default: break
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        switch command {
        case .besTaban: Text("Diagram: the kenei lies just inside the circle line. The thrower stands five feet along the circle from it, on either side, and throws at it.")
        case .diagonal: Text("Diagram: the kenei lies between the kon and the circle. The thrower stands on the opposite side of the circle and throws across the kon at it.")
        case .parallel: Text("Diagram: the kenei lies between the parallel lines. The thrower stands on the circle's wing, in line with the kon, and throws along the lines at it.")
        default: Text("Diagram of the field: the circle with the kon in the middle.")
        }
    }
}

/// Drawing in meters on the field, mapped onto the canvas: x to the right, z toward the home
/// thrower (down on screen), the kon at the center.
private struct Sketch {
    let size: CGSize
    let category: AgeCategory
    let center: CGPoint
    /// Points per meter.
    let scale: Double
    let radius: Double

    init(size: CGSize, category: AgeCategory) {
        self.size = size
        self.category = category
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = Double(category.circleRadius)
        // Room around the circle for the throw spots and their marks.
        scale = min(size.width, size.height) / 2 / (radius + 0.42)
    }

    /// Lines thicken a little on a bigger canvas, so the sketch reads the same at any size.
    private var weight: Double {
        max(min(size.width / 160, 1.6), 0.8)
    }

    func point(_ x: Double, _ z: Double) -> CGPoint {
        CGPoint(x: center.x + x * scale, y: center.y + z * scale)
    }

    /// A point on the circle at `angle` radians, counterclockwise from +x as seen on screen.
    func onCircle(_ angle: Double, radius r: Double? = nil) -> CGPoint {
        let distance = r ?? radius
        return point(cos(angle) * distance, -sin(angle) * distance)
    }

    // MARK: The field

    func drawField(in context: inout GraphicsContext) {
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(
            Path(roundedRect: bounds, cornerRadius: size.width * 0.12, style: .continuous),
            with: .linearGradient(
                Gradient(colors: [Palette.felt.color.opacity(0.88), Palette.felt.color]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        let r = radius * scale
        let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        context.stroke(circle, with: .color(Palette.thread.color.opacity(0.95)), style: StrokeStyle(lineWidth: 1.6 * weight, dash: [5 * weight, 2.2 * weight]))

        // The throw axis, faint.
        var axis = Path()
        axis.move(to: point(0, -radius))
        axis.addLine(to: point(0, radius))
        context.stroke(axis, with: .color(Palette.thread.color.opacity(0.25)), style: StrokeStyle(lineWidth: 0.6 * weight, dash: [2 * weight, 3 * weight]))

        let half = Double(category.konLength) / 2
        // The parallel lines, spread a touch wider than true scale so the band can be seen.
        let band = max(Double(FieldGeometry.parallelLineOffset), 4.5 / scale)
        for offset in [-band, band] {
            var line = Path()
            line.move(to: point(-half, offset))
            line.addLine(to: point(half, offset))
            context.stroke(line, with: .color(Palette.thread.color.opacity(0.75)), style: StrokeStyle(lineWidth: 0.8 * weight, lineCap: .round, dash: [2.5 * weight, 2 * weight]))
        }

        // The kon: the row of kenei.
        let count = category.keneiCount
        let spacing = 2 * half / Double(count - 1)
        let dot = max(1.1 * weight, 0.018 * scale)
        for index in 0..<count {
            let at = point(-half + Double(index) * spacing, 0)
            context.fill(Path(ellipseIn: CGRect(x: at.x - dot, y: at.y - dot, width: 2 * dot, height: 2 * dot)), with: .color(Palette.bone.color))
        }
    }

    // MARK: Commands

    /// The kenei lies just inside the circle line; five tabans along the circle either way are
    /// the two places to throw from (каз. п. 2.1).
    func drawBesTaban(in context: inout GraphicsContext) {
        let keneiAngle = -0.95
        let kenei = onCircle(keneiAngle, radius: radius - 0.14)
        let taban = Double(GameTuning.Rules.taban)
        let step = taban / radius
        // The five feet paced out along the circle, each way.
        for direction in [-1.0, 1.0] {
            for foot in 1...5 {
                let angle = keneiAngle + direction * Double(foot) * step
                var tick = Path()
                tick.move(to: onCircle(angle, radius: radius + 0.05))
                tick.addLine(to: onCircle(angle, radius: radius + 0.16))
                context.stroke(tick, with: .color(Palette.paper.color.opacity(foot == 5 ? 0.95 : 0.55)), style: StrokeStyle(lineWidth: 1.1 * weight, lineCap: .round))
            }
        }
        for direction in [-1.0, 1.0] {
            let spot = onCircle(keneiAngle + direction * 5 * step, radius: radius + 0.3)
            drawArrow(from: spot, to: kenei, in: &context)
            drawSpot(spot, in: &context)
        }
        drawKenei(kenei, in: &context)
    }

    /// The kenei lies between the kon and the circle; the throw comes from the far side of the
    /// circle, across the kon (п. 2.2).
    func drawDiagonal(in context: inout GraphicsContext) {
        let angle = 1.1
        let kenei = onCircle(angle, radius: radius * 0.55)
        let spot = onCircle(angle + .pi, radius: radius + 0.3)
        drawArrow(from: spot, to: kenei, in: &context)
        drawSpot(spot, in: &context)
        drawKenei(kenei, in: &context)
    }

    /// The kenei lies between the parallel lines; the throw comes from the circle's wing,
    /// along the band (п. 2.3).
    func drawParallel(in context: inout GraphicsContext) {
        let half = Double(category.konLength) / 2
        let kenei = point(-half * 0.7, 0.04)
        let spot = point(radius + 0.3, 0)
        drawArrow(from: spot, to: kenei, in: &context)
        drawSpot(spot, in: &context)
        drawKenei(kenei, in: &context)
    }

    // MARK: Marks

    /// The fallen kenei, glowing like the one the game asks you to hit.
    private func drawKenei(_ at: CGPoint, in context: inout GraphicsContext) {
        let glow = 7.5 * weight
        context.fill(Path(ellipseIn: CGRect(x: at.x - glow, y: at.y - glow, width: 2 * glow, height: 2 * glow)), with: .color(Palette.accent.color.opacity(0.28)))
        let body = CGRect(x: at.x - 3.6 * weight, y: at.y - 2.6 * weight, width: 7.2 * weight, height: 5.2 * weight)
        context.fill(Path(roundedRect: body, cornerRadius: 1.8 * weight, style: .continuous), with: .color(Palette.bone.color))
        context.stroke(Path(roundedRect: body, cornerRadius: 1.8 * weight, style: .continuous), with: .color(Palette.accent.color), lineWidth: 1.2 * weight)
    }

    /// Where the thrower stands.
    private func drawSpot(_ at: CGPoint, in context: inout GraphicsContext) {
        let r = 4.2 * weight
        let disk = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
        context.fill(disk, with: .color(Palette.saqa.color))
        context.stroke(disk, with: .color(Palette.paper.color), lineWidth: 1.4 * weight)
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let ux = dx / length
        let uy = dy / length
        // Stop short of the spot and the kenei so neither is covered.
        let from = CGPoint(x: start.x + ux * 6 * weight, y: start.y + uy * 6 * weight)
        let tip = CGPoint(x: end.x - ux * 9 * weight, y: end.y - uy * 9 * weight)
        var shaft = Path()
        shaft.move(to: from)
        shaft.addLine(to: tip)
        context.stroke(shaft, with: .color(Palette.paper.color), style: StrokeStyle(lineWidth: 1.5 * weight, lineCap: .round))
        let head = 5 * weight
        var arrowhead = Path()
        arrowhead.move(to: CGPoint(x: tip.x + ux * head * 0.6, y: tip.y + uy * head * 0.6))
        arrowhead.addLine(to: CGPoint(x: tip.x - ux * head * 0.6 - uy * head * 0.55, y: tip.y - uy * head * 0.6 + ux * head * 0.55))
        arrowhead.addLine(to: CGPoint(x: tip.x - ux * head * 0.6 + uy * head * 0.55, y: tip.y - uy * head * 0.6 - ux * head * 0.55))
        arrowhead.closeSubpath()
        context.fill(arrowhead, with: .color(Palette.paper.color))
    }
}

#Preview {
    HStack(spacing: 12) {
        CommandDiagram(command: .besTaban)
        CommandDiagram(command: .diagonal)
        CommandDiagram(command: .parallel, category: .bala)
    }
    .padding()
}
