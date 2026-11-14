import SwiftUI

/// What the referee just called, for the banner.
struct RefereeBanner: Equatable {
    var call: RefereeCall
    /// The call as this player reads it: meaning first until they know the word.
    var headline: TermHeadline
    /// How the saqa came to rest, as the referee would call it.
    var saqaSide: Side?
    /// Changes on every call, so the same call twice still animates.
    var serial: Int

    /// A banner for `call`, counting it as seen by the player.
    init(call: RefereeCall, saqaSide: Side?, serial: Int) {
        self.call = call
        self.saqaSide = saqaSide
        self.serial = serial
        let term = call.term
        headline = TermHeadline(term, learned: TermFamiliarity.isLearned(term), detail: call.detail, exclaimed: call.isExclaimed)
        TermFamiliarity.markSeen(term)
    }
}

extension RefereeCall {
    var term: Term {
        switch self {
        case .out, .partiaWon, .matchWon: .shyqty
        case .miss: .timedi
        case .slide: .syrgytpa
        case .besTaban: .besTaban
        case .diagonal: .diagonal
        case .parallel: .parallel
        }
    }

    /// What to say under the word once the player knows it.
    var detail: LocalizedStringResource {
        switch self {
        case .out, .partiaWon, .matchWon: "out of the circle"
        case .miss: "the kenei go back"
        case .slide: "slid in along the carpet — doesn't count"
        case .besTaban: "one more throw, five feet along the circle"
        case .diagonal: "one more throw, from the far side"
        case .parallel: "one more throw, from the circle's wing"
        }
    }

    var isExclaimed: Bool {
        self != .miss
    }
}

/// The referee's call, slammed onto the screen: the headline, what it means, his gesture.
struct RefereeBannerView: View {
    let banner: RefereeBanner

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
            Text(verbatim: banner.headline.title)
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
            Text(verbatim: banner.headline.detail)
                .font(Typography.label)
                .foregroundStyle(Palette.paper.color.opacity(0.9))
                .multilineTextAlignment(.center)
            if let side = banner.saqaSide {
                HStack(spacing: 8) {
                    Text(verbatim: Term.saqa.label)
                        .foregroundStyle(Palette.ink.color.opacity(0.55))
                    SideLabel(side: side)
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

/// Which side beats which, in dots: readable without a word of Kazakh. One row where it
/// fits, two where it doesn't.
struct RankingLegend: View {
    private let sides: [Side] = [.alshy, .taike, .buk, .shik]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { items(sides) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { items(Array(sides.prefix(2)), trailing: true) }
                HStack(spacing: 10) { items(Array(sides.suffix(2))) }
            }
        }
        .font(Typography.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Alshy beats taike, taike beats buk, buk beats shik"))
    }

    @ViewBuilder
    private func items(_ group: [Side], trailing: Bool = false) -> some View {
        ForEach(group, id: \.self) { side in
            SideLabel(side: side)
            if side != group.last || trailing {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.ink.color.opacity(0.35))
            }
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
        case .besTaban: Text(verbatim: Term.besTaban.label)
        case .diagonal: Text(verbatim: Term.diagonal.label)
        case .parallel: Text(verbatim: Term.parallel.label)
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

/// «Тарт та жібер»: shown until the first throw. The instruction in the player's language,
/// the Kazakh words under it.
struct PullHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.paper.color.opacity(0.9))
                .phaseAnimator([0, 1]) { content, phase in
                    content.offset(y: phase * 8).opacity(1 - phase * 0.4)
                } animation: { _ in .easeInOut(duration: 0.9) }
            Group {
                if TermLanguage.current == .kazakh {
                    Text(verbatim: Term.tartTaZhiber.kazakh)
                } else {
                    Text(Term.tartTaZhiber.call)
                }
            }
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(Palette.paper.color)
            Group {
                if TermLanguage.current == .kazakh {
                    Text(Term.tartTaZhiber.explanation)
                } else {
                    Text(verbatim: Term.tartTaZhiber.word)
                }
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.paper.color.opacity(0.8))
        }
        .multilineTextAlignment(.center)
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

/// Иіру: a quick flick anywhere spins the saqa; faster spins harder, the flick's lean tilts it.
struct FlickSurface: View {
    let onFlick: (_ strength: Float, _ tilt: Float) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let velocity = value.velocity
                        let speed = (velocity.width * velocity.width + velocity.height * velocity.height).squareRoot()
                        guard speed > 250 else { return }
                        let strength = min(Double(speed) / GameTuning.Iiru.fullFlick, 1)
                        onFlick(Float(strength), Float(velocity.width / speed))
                    }
            )
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
