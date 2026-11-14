import SwiftUI

/// «How to play» on the real arena, one step at a time.
struct LessonScreen: View {
    @State private var controller = LessonController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `true` to go straight into a match.
    var onFinish: (_ play: Bool) -> Void

    var body: some View {
        ZStack {
            ArenaView(stage: controller.stage)
                .ignoresSafeArea()
            ArenaVignette()
            if controller.step.isThrow {
                SlingshotSurface(stage: controller.stage)
            } else if controller.canSpin {
                FlickSurface { strength, tilt in controller.spin(strength: strength, tilt: tilt) }
            }
            overlay
            #if DEBUG
            FrameRateBadge(stage: controller.stage)
            #endif
        }
        .statusBarHidden()
        .defersSystemGestures(on: .bottom)
        .onAppear { controller.stage.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in controller.stage.reduceMotion = newValue }
    }

    private var overlay: some View {
        VStack(spacing: 12) {
            HStack {
                GlassIconButton(systemName: "xmark", label: "Skip the lesson") {
                    controller.stop()
                    onFinish(false)
                }
                Spacer()
                LessonProgress(current: controller.step.progress, count: LessonController.Step.count)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.top, 8)
            ZStack(alignment: .top) {
                if let banner = controller.banner {
                    RefereeBannerView(banner: banner)
                        .id(banner.serial)
                        .transition(.asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
                } else if controller.step.isThrow {
                    ThrowGoal(step: controller.step)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if controller.step == .iiru || controller.step == .meet {
                    // Up top, so the saqa in the hand and the spinning one stay in view.
                    card
                }
            }
            .animation(Motion.slam, value: controller.banner)
            .frame(maxHeight: .infinity, alignment: .top)
            if controller.step.isThrow {
                PullArea(stage: controller.stage, showsHint: true)
            } else if controller.banner == nil, controller.step != .iiru, controller.step != .meet {
                card
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 16)
        .overlay {
            if controller.step == .meet {
                MeetCallouts()
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: controller.step)
    }

    private var card: some View {
        LessonCard(step: controller.step, category: controller.category, onNext: controller.next) { play in
            controller.stop()
            onFinish(play)
        }
        .id(controller.step)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Dots for the lesson's steps.
private struct LessonProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Palette.ink.color : Palette.ink.color.opacity(0.2))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .glassCapsule()
        .animation(Motion.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current + 1) of \(count)"))
    }
}

/// What to do on a throw step.
private struct ThrowGoal: View {
    let step: LessonController.Step

    var body: some View {
        VStack(spacing: 2) {
            Text(step == .series ? "Again — now from the circle's edge" : "Knock a kenei out of the circle")
                .font(.system(.headline, design: .rounded))
            Text("Pull down for power, sideways to aim")
                .font(Typography.caption)
                .foregroundStyle(Palette.ink.color.opacity(0.6))
        }
        .foregroundStyle(Palette.ink.color)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Names the bones on screen in the first step. The aiming camera always puts the kon at the
/// center and the hand low in the middle, so the labels can sit at fixed places.
private struct MeetCallouts: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            callout(.kenei, pointing: .down)
                .position(x: size.width / 2, y: size.height * 0.5 + 64)
            callout(.saqa, pointing: .down)
                .position(x: size.width / 2, y: size.height * 0.84 - 64)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private enum Pointing { case down }

    private func callout(_ term: Term, pointing: Pointing) -> some View {
        VStack(spacing: 2) {
            VStack(spacing: 0) {
                Text(verbatim: term.word)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(term.gloss)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink.color.opacity(0.6))
            }
            .foregroundStyle(Palette.ink.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassCapsule()
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9))
                .foregroundStyle(Palette.paper.color.opacity(0.9))
        }
    }
}

/// The explanation for a step, with its button.
private struct LessonCard: View {
    let step: LessonController.Step
    let category: AgeCategory
    let onNext: () -> Void
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            bodyText
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.ink.color.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            accessory
            buttons
        }
        .padding(22)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Palette.ink.color.opacity(0.18), radius: 24, y: 8)
    }

    // MARK: Parts

    @ViewBuilder
    private var header: some View {
        switch step {
        case .meet: TermTitle(term: .asyqAtu)
        case .shyqty: TermTitle(term: .shyqty, exclaimed: true)
        case .timedi: TermTitle(term: .timedi)
        case .syrgytpa: TermTitle(term: .syrgytpa, exclaimed: true)
        case .seriesResult(let knockedOut): TermTitle(term: knockedOut ? .shyqty : .timedi, exclaimed: knockedOut)
        case .goal: PlainTitle(text: Text("How to win"))
        case .iiru: TermTitle(term: .iiru)
        case .iiruResult(let side):
            VStack(alignment: .leading, spacing: 6) {
                Text("Your saqa landed")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink.color.opacity(0.6))
                SideLabel(side: side)
                    .font(.system(.title, design: .rounded).weight(.heavy))
            }
        case .commands: PlainTitle(text: Text("The referee's calls"))
        case .done: PlainTitle(text: Text("You're ready"))
        case .firstThrow, .series: EmptyView()
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        switch step {
        case .meet:
            Text("The Kazakh game of knucklebones. Stand at the line, throw your saqa and knock the kenei out of the circle.")
        case .shyqty:
            Text(Term.shyqty.explanation)
        case .timedi:
            Text("\(Text(Term.timedi.explanation)) In a match your rival would throw now — here, just try again.")
        case .syrgytpa:
            Text("\(Text(Term.syrgytpa.explanation)) Pull a little harder, so the saqa flies into the circle.")
        case .seriesResult(let knockedOut):
            knockedOut
                ? Text("As long as you knock kenei out, you keep throwing. That's your series.")
                : Text("Your series ends here, and your rival takes the next throw.")
        case .goal:
            Text("Knock out \(category.winningCount) of the \(category.keneiCount) kenei first to win a round — adults play to 8 of 15. Win two rounds to win the match.")
        case .iiru:
            Text("\(Text(Term.iiru.explanation)) Flick the screen to spin yours.")
        case .iiruResult(let side):
            Text("\(Text(Term(side).explanation)) The higher side throws first.")
        case .commands:
            Text("If your saqa hits a kenei that stays inside the circle, the referee gives you one more throw at it, from a new spot:")
        case .done:
            Text("Play your first match. Tips will show up the first time something happens.")
        case .firstThrow, .series:
            EmptyView()
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch step {
        case .goal:
            GoalRow(category: category)
        case .iiru:
            RankingLegend()
        case .commands:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach([RefereeCall.besTaban, .diagonal, .parallel], id: \.self) { command in
                        VStack(alignment: .leading, spacing: 6) {
                            CommandDiagram(command: command)
                                .frame(width: 150, height: 150)
                            Text(verbatim: command.term.word)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                            Text(command.term.name)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.ink.color.opacity(0.6))
                        }
                        .foregroundStyle(Palette.ink.color)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .iiru:
            EmptyView()
        case .done:
            VStack(spacing: 4) {
                PrimaryButton(title: Text("Play a match")) { onFinish(true) }
                Button { onFinish(false) } label: {
                    Text("Menu")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Palette.ink.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        default:
            PrimaryButton(title: buttonTitle, action: onNext)
        }
    }

    private var buttonTitle: Text {
        switch step {
        case .meet: Text("Let's throw")
        case .shyqty: Text("Throw from the edge")
        case .timedi, .syrgytpa: Text("Try again")
        case .commands: Text("Got it")
        default: Text("Next")
        }
    }
}

/// A term as a card title: the word big, its meaning under it (or the reverse for a new word).
private struct TermTitle: View {
    let term: Term
    var exclaimed = false

    var body: some View {
        let headline = TermHeadline(term, learned: true, exclaimed: exclaimed)
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: headline.title)
                .font(.system(.largeTitle, design: .rounded).weight(.black))
                .foregroundStyle(Palette.ink.color)
            if TermLanguage.current != .kazakh {
                Text(verbatim: term.quotedGloss)
                    .font(Typography.label)
                    .foregroundStyle(Palette.ink.color.opacity(0.55))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlainTitle: View {
    let text: Text

    var body: some View {
        text
            .font(.system(.title, design: .rounded).weight(.heavy))
            .foregroundStyle(Palette.ink.color)
    }
}

/// The kon's kenei as glyphs, the ones you need to win in the accent color.
private struct GoalRow: View {
    let category: AgeCategory

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<category.keneiCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index < category.winningCount ? Palette.accent.color : Palette.bone.color)
                    .frame(width: 14, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Palette.ink.color.opacity(0.15), lineWidth: 0.5))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The ink capsule button used across the app's cards.
struct PrimaryButton: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            title
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Palette.paper.color)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Palette.ink.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
