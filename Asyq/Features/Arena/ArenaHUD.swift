import SwiftUI

/// What the referee just called, for the banner.
struct RefereeBanner: Equatable {
    var call: RefereeCall
    /// How the saqa came to rest, as the referee would call it.
    var saqaSide: Side?
    /// Changes on every call, so the same call twice still animates.
    var serial: Int
}

/// The referee's call, slammed onto the screen: the Kazakh word, what it means, his gesture.
struct RefereeBannerView: View {
    let banner: RefereeBanner
    var rivalName: String = ""

    var body: some View {
        VStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink.color)
                    .frame(width: 56, height: 56)
                    .glassCircle()
                    .padding(.bottom, 6)
            }
            Text(verbatim: title)
                .font(Typography.call)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Palette.paper.color)
            if case .out(let count) = banner.call {
                Text(verbatim: "+\(count)")
                    .font(Typography.callDetail)
                    .foregroundStyle(Palette.paper.color)
            }
            Text(subtitle)
                .font(Typography.label)
                .foregroundStyle(Palette.paper.color.opacity(0.88))
                .multilineTextAlignment(.center)
            if let side = banner.saqaSide {
                HStack(spacing: 6) {
                    Text(verbatim: "Сақа")
                        .foregroundStyle(Palette.ink.color.opacity(0.55))
                    Text(verbatim: side.term)
                        .foregroundStyle(Palette.ink.color)
                }
                .font(Typography.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassCapsule()
                .padding(.top, 10)
            }
        }
        .shadow(color: Palette.ink.color.opacity(0.35), radius: 14, y: 4)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch banner.call {
        case .out: "ШЫҚТЫ!"
        case .miss: "ТИМЕДІ"
        case .slide: "СЫРҒЫТПА!"
        case .besTaban: "БЕС ТАБАН!"
        case .diagonal: "ДИАГОНАЛЬ!"
        case .parallel: "ПАРАЛЛЕЛЬ!"
        case .partiaWon, .matchWon: "ЖАРАЙСЫҢ!"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch banner.call {
        case .out: "Out of the circle"
        case .miss: "Missed — the kenei go back"
        case .slide: "The saqa slid in along the carpet — doesn't count"
        case .besTaban: "Five feet along the circle — one more throw"
        case .diagonal: "From across the circle — one more throw"
        case .parallel: "Between the lines — one more throw from the wing"
        case .partiaWon, .matchWon: ""
        }
    }

    /// Stand-ins for the referee's hand signs (Регламент, с. 24–25) until we draw our own.
    private var symbol: String? {
        switch banner.call {
        case .besTaban: "figure.walk"
        case .diagonal: "arrow.up.right"
        case .parallel: "equal"
        case .slide: "exclamationmark.triangle"
        default: nil
        }
    }
}

/// Where the next throw comes from, and how far.
struct SpotChip: View {
    let spot: ThrowSpot
    let distance: Float

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink.color.opacity(0.6))
            Text(Measurement(value: Double(distance), unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
                .font(Typography.score)
                .foregroundStyle(Palette.ink.color)
                .contentTransition(.numericText(value: Double(distance)))
                .fixedSize()
            // The caption gives way first on narrow phones and big text sizes.
            ViewThatFits(in: .horizontal) {
                caption
                    .lineLimit(1)
                    .fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.ink.color.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassCapsule()
        .animation(Motion.bouncy, value: distance)
    }

    private var icon: String {
        switch spot {
        case .line: "line.horizontal.3"
        case .circleEdge: "circle.dashed"
        case .besTaban: "figure.walk"
        case .diagonal: "arrow.up.right"
        case .parallel: "equal"
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch spot {
        case .line: Text("from the line")
        case .circleEdge: Text("from the circle")
        case .besTaban: Text(verbatim: "Бес табан")
        case .diagonal: Text(verbatim: "Диагональ")
        case .parallel: Text(verbatim: "Параллель")
        }
    }
}

/// How far the throw will go, while pulling.
struct RangeReadout: View {
    let range: Float
    let power: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.ink.color.opacity(0.55))
            Text(Measurement(value: Double(range), unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
                .font(Typography.score)
                .foregroundStyle(Palette.ink.color)
                .contentTransition(.numericText(value: Double(range)))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassCapsule()
        .scaleEffect(1 + 0.06 * power)
    }
}

/// «Тарт та жібер»: shown until the first throw.
struct PullHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.paper.color.opacity(0.9))
                .phaseAnimator([0, 1]) { content, phase in
                    content.offset(y: phase * 8).opacity(1 - phase * 0.4)
                } animation: { _ in .easeInOut(duration: 0.9) }
            Text(verbatim: "Тарт та жібер")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.paper.color)
            Text("Pull down, then let go")
                .font(Typography.caption)
                .foregroundStyle(Palette.paper.color.opacity(0.8))
        }
        .shadow(color: Palette.ink.color.opacity(0.3), radius: 10, y: 3)
        .padding(.bottom, 4)
    }
}

/// A round glass button with an icon, for the top bar.
struct GlassIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.color)
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// The slingshot: a drag anywhere on the screen.
struct SlingshotSurface: View {
    let stage: ArenaStage

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if stage.pullPower == nil {
                            stage.beginPull(at: value.startLocation)
                        }
                        stage.updatePull(to: value.location)
                    }
                    .onEnded { value in
                        stage.endPull(velocity: CGVector(dx: value.velocity.width, dy: value.velocity.height))
                    }
            )
            .allowsHitTesting(stage.canPull)
    }
}

/// Darkens the corners a touch, like a lens: keeps the eye on the kon.
struct ArenaVignette: View {
    var body: some View {
        RadialGradient(
            colors: [.clear, Palette.ink.color.opacity(0.18)],
            center: .center,
            startRadius: 180,
            endRadius: 620
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The pull readout or the hint, above the saqa in the hand.
struct PullArea: View {
    let stage: ArenaStage
    let showsHint: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if let power = stage.pullPower, power > 0.02 {
                RangeReadout(range: stage.pullRange, power: power)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if showsHint, stage.canPull {
                PullHint()
                    .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: stage.pullPower == nil)
        .animation(Motion.smooth, value: showsHint && stage.canPull)
        .frame(height: 120, alignment: .bottom)
        // Clear of the saqa in the hand, which sits just below.
        .padding(.bottom, 150)
    }
}

#if DEBUG
/// Frames per second, bottom left, in Debug builds only.
struct FrameRateBadge: View {
    let stage: ArenaStage

    var body: some View {
        Text(verbatim: "\(stage.framesPerSecond) fps")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Palette.ink.color.opacity(0.5))
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
    }
}
#endif
