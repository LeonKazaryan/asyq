import SwiftUI

/// Everything over the arena: where you throw from, the score, the referee's call, the hint.
/// Quiet while you aim, loud only when something happens (docs/02-design.md).
struct PracticeHUD: View {
    let controller: PracticeController

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            ZStack {
                if let banner = controller.banner {
                    CallBanner(banner: banner)
                        .id(banner.serial)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.6).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
            }
            .animation(Motion.slam, value: controller.banner)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
            bottomArea
        }
        .padding(.horizontal, 16)
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            Text(verbatim: "\(controller.framesPerSecond) fps")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Palette.ink.color.opacity(0.5))
                .padding(.leading, 20)
        }
        #endif
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            SpotChip(distance: controller.throwDistance, isFromEdge: controller.isFromEdge)
            Spacer()
            ScoreChip(knockedOut: controller.knockedOut, total: controller.category.keneiCount)
            Button {
                controller.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.color)
                    .frame(width: 44, height: 44)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .disabled(!controller.canThrow)
            .accessibilityLabel(Text("Start over"))
        }
        .padding(.top, 8)
    }

    // MARK: - Bottom

    private var bottomArea: some View {
        ZStack(alignment: .bottom) {
            if let power = controller.pullPower, power > 0.02 {
                RangeReadout(range: controller.pullRange, power: power)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if controller.showsHint {
                PullHint()
                    .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: controller.pullPower == nil)
        .animation(Motion.smooth, value: controller.showsHint)
        .frame(height: 120, alignment: .bottom)
        // Clear of the saqa in the hand, which sits just below.
        .padding(.bottom, 150)
    }
}

/// «6 м» and where from: the line, or the circle's edge in a series.
private struct SpotChip: View {
    let distance: Float
    let isFromEdge: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isFromEdge ? "circle.dashed" : "line.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink.color.opacity(0.6))
            Text(Measurement(value: Double(distance), unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
                .font(Typography.score)
                .foregroundStyle(Palette.ink.color)
                .contentTransition(.numericText(value: Double(distance)))
                .fixedSize()
            // The caption gives way first on narrow phones and big text sizes.
            ViewThatFits(in: .horizontal) {
                Text(isFromEdge ? "from the circle" : "from the line")
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
        .animation(Motion.bouncy, value: isFromEdge)
    }
}

/// Kenei knocked out so far.
private struct ScoreChip: View {
    let knockedOut: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(Palette.bone.color)
                .frame(width: 14, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(Palette.ink.color.opacity(0.15), lineWidth: 0.5))
            Text(verbatim: "\(knockedOut)")
                .font(Typography.score)
                .foregroundStyle(Palette.ink.color)
                .contentTransition(.numericText(value: Double(knockedOut)))
            Text(verbatim: "/ \(total)")
                .font(Typography.caption)
                .foregroundStyle(Palette.ink.color.opacity(0.5))
        }
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassCapsule()
        .animation(Motion.bouncy, value: knockedOut)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(knockedOut) of \(total) knocked out"))
    }
}

/// The referee's call, slammed onto the screen.
private struct CallBanner: View {
    let banner: PracticeController.Banner

    var body: some View {
        VStack(spacing: 4) {
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
                .foregroundStyle(Palette.paper.color.opacity(0.85))
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
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch banner.call {
        case .out: "ШЫҚТЫ!"
        case .miss: "ТИМЕДІ"
        case .cleared: "БӘРІ ШЫҚТЫ!"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch banner.call {
        case .out: "Out of the circle"
        case .miss: "Missed — the kenei go back"
        case .cleared: "The kon is clear"
        }
    }
}

/// How far the throw will go, while pulling.
private struct RangeReadout: View {
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
private struct PullHint: View {
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
