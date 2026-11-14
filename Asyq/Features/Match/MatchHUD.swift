import SwiftUI

/// Everything over the arena during a match: the scoreboard, where the throw comes from, the
/// referee, иіру, and the partia and match results.
struct MatchHUD: View {
    let controller: MatchController
    var onClose: () -> Void
    var onRematch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GlassIconButton(systemName: "chevron.left", label: "Back", action: onClose)
                Scoreboard(controller: controller)
            }
            .padding(.top, 8)
            if controller.moment == .playing, controller.stage.aim != nil, controller.banner == nil {
                HStack(spacing: 10) {
                    SpotChip(spot: controller.match.spot, distance: controller.throwDistance)
                    if controller.canSwitchFlank {
                        GlassIconButton(systemName: "arrow.left.arrow.right", label: "Throw from the other side") {
                            controller.switchFlank()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .animation(Motion.snappy, value: controller.canSwitchFlank)
                .transition(.opacity)
            }
            if let tip = controller.tip, controller.banner == nil, controller.moment == .playing {
                TipCard(tip: tip, onDismiss: controller.dismissTip)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            center
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            bottom
        }
        .padding(.horizontal, 16)
        .animation(Motion.smooth, value: controller.moment)
        .animation(Motion.bouncy, value: controller.tip)
        // Pulling the slingshot means the tip was read.
        .onChange(of: controller.stage.pullPower != nil) { _, pulling in
            if pulling { controller.dismissTip() }
        }
    }

    @ViewBuilder
    private var center: some View {
        ZStack {
            switch controller.moment {
            case .iiru(let round):
                IiruPanel(round: round, rivalName: controller.rivalName)
                    .transition(.opacity)
            case .playing:
                if let banner = controller.banner {
                    RefereeBannerView(banner: banner)
                        .id(banner.serial)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.6).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                } else if let player = controller.turnNotice {
                    TurnNotice(name: controller.name(of: player), isHome: player == .home)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            case .partiaOver(let winner):
                ResultCard(
                    title: Text("Round \(controller.match.partia)"),
                    headline: winner == .home ? Text("You won it") : Text("\(controller.rivalName) won it"),
                    score: controller.match,
                    primary: (Text("Next partia"), controller.continueAfterPartia),
                    secondary: nil
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            case .matchOver(let winner):
                ResultCard(
                    title: Text(verbatim: controller.finalHeadline?.title ?? ""),
                    headline: winner == .home ? Text("You won the match") : Text("\(controller.rivalName) won the match"),
                    score: controller.match,
                    primary: (Text("Play again"), onRematch),
                    secondary: (Text("Menu"), onClose)
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(Motion.slam, value: controller.banner)
        .animation(Motion.bouncy, value: controller.turnNotice)
    }

    @ViewBuilder
    private var bottom: some View {
        if controller.moment == .playing, controller.match.thrower == .away, controller.banner == nil, controller.stage.aim != nil {
            HStack(spacing: 8) {
                ProgressView().tint(Palette.ink.color)
                Text("\(controller.rivalName) is aiming")
                    .font(Typography.label)
                    .foregroundStyle(Palette.ink.color)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassCapsule()
            .padding(.bottom, 40)
            .transition(.opacity)
        } else {
            PullArea(stage: controller.stage, showsHint: controller.showsHint && controller.moment == .playing)
        }
    }
}

/// Both players: partias won, kenei out this partia, and who is throwing.
private struct Scoreboard: View {
    let controller: MatchController

    var body: some View {
        HStack(spacing: 0) {
            side(.home)
            VStack(spacing: 2) {
                Text("Round \(controller.match.partia)")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.ink.color.opacity(0.55))
                Text(verbatim: "/ \(controller.category.winningCount)")
                    .font(.system(.caption2, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(Palette.ink.color.opacity(0.4))
            }
            .fixedSize()
            .padding(.horizontal, 6)
            side(.away)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .glassCapsule()
    }

    private func side(_ player: Player) -> some View {
        let isThrowing = controller.moment == .playing && controller.match.thrower == player
        let score = controller.match.score[player] ?? 0
        let wins = controller.match.partiaWins[player] ?? 0
        return HStack(spacing: 8) {
            if player == .away { Spacer(minLength: 0) }
            if player == .away {
                Text(verbatim: "\(score)").modifier(ScoreDigits(value: score))
            }
            VStack(alignment: player == .home ? .leading : .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill((player == .home ? Palette.saqa : Palette.rivalSaqa).color)
                        .frame(width: 8, height: 8)
                    Text(verbatim: controller.name(of: player))
                        .font(Typography.caption)
                        .lineLimit(1)
                }
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { index in
                        Capsule()
                            .fill(index < wins ? Palette.accent.color : Palette.ink.color.opacity(0.15))
                            .frame(width: 12, height: 4)
                    }
                }
            }
            .foregroundStyle(Palette.ink.color)
            if player == .home {
                Text(verbatim: "\(score)").modifier(ScoreDigits(value: score))
            }
            if player == .home { Spacer(minLength: 0) }
        }
        .opacity(isThrowing || controller.moment != .playing ? 1 : 0.5)
        .animation(Motion.smooth, value: isThrowing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(controller.name(of: player)): \(score), partias \(wins)"))
    }
}

private struct ScoreDigits: ViewModifier {
    let value: Int

    func body(content: Content) -> some View {
        content
            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Palette.ink.color)
            .contentTransition(.numericText(value: Double(value)))
            .animation(Motion.bouncy, value: value)
    }
}

/// «Кезек»: whose turn it is now.
private struct TurnNotice: View {
    let name: String
    let isHome: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: Term.kezek.word.uppercased())
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .tracking(2)
                .foregroundStyle(Palette.paper.color.opacity(0.8))
            Text(isHome ? "Your throw" : "\(name)’s throw")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.paper.color)
        }
        .shadow(color: Palette.ink.color.opacity(0.35), radius: 12, y: 3)
    }
}

/// Who starts: flick your saqa, then the rival spins theirs; the higher side starts.
private struct IiruPanel: View {
    let round: MatchController.IiruRound
    let rivalName: String

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(verbatim: round.headline.title)
                    .font(Typography.call)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Palette.paper.color)
                Text(verbatim: round.headline.detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.paper.color.opacity(0.8))
                Text(subtitle)
                    .font(Typography.label)
                    .foregroundStyle(Palette.paper.color.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .contentTransition(.opacity)
            }
            .shadow(color: Palette.ink.color.opacity(0.35), radius: 12, y: 3)
            HStack(spacing: 10) {
                SideChip(name: Text("You"), side: round.home, color: Palette.saqa.color)
                SideChip(name: Text(verbatim: rivalName), side: round.away, color: Palette.rivalSaqa.color)
            }
            .animation(Motion.bouncy, value: round)
            RankingLegend()
        }
    }

    private var subtitle: LocalizedStringKey {
        switch round.decided {
        case .some(.some(.home)): "Your side is higher — you start"
        case .some(.some(.away)): "\(rivalName)’s side is higher — they start"
        case .some(.none): "Same rank — spin again"
        case .none: round.home == nil ? "Who starts? Flick to spin your saqa" : "\(rivalName) spins…"
        }
    }
}

private struct SideChip: View {
    let name: Text
    let side: Side?
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            name
                .foregroundStyle(Palette.ink.color.opacity(0.6))
            if let side {
                SideLabel(side: side)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(verbatim: "…").foregroundStyle(Palette.ink.color.opacity(0.4))
            }
        }
        .font(Typography.label)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glassCapsule()
    }
}

/// A one-time explanation, under the scoreboard.
private struct TipCard: View {
    let tip: MatchTip
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let command = tip.command {
                CommandDiagram(command: command)
                    .frame(width: 84, height: 84)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tip.title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    if let term = tip.term {
                        Text(verbatim: term.word)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ink.color.opacity(0.5))
                    }
                }
                Text(tip.message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.ink.color.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.ink.color.opacity(0.5))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Got it"))
        }
        .foregroundStyle(Palette.ink.color)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.ink.color.opacity(0.15), radius: 16, y: 6)
    }
}

/// The end of a partia or of the match.
private struct ResultCard: View {
    let title: Text
    let headline: Text
    let score: BesTabanMatch
    let primary: (Text, () -> Void)
    let secondary: (Text, () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            title
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Palette.ink.color.opacity(0.6))
            headline
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink.color)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Text(verbatim: "\(score.partiaWins[.home] ?? 0)")
                Text(verbatim: ":").foregroundStyle(Palette.ink.color.opacity(0.4))
                Text(verbatim: "\(score.partiaWins[.away] ?? 0)")
            }
            .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(Palette.ink.color)
            Button(action: primary.1) {
                primary.0
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Palette.paper.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.ink.color, in: Capsule())
            }
            .buttonStyle(.plain)
            if let secondary {
                Button(action: secondary.1) {
                    secondary.0
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Palette.ink.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Palette.ink.color.opacity(0.2), radius: 30, y: 10)
    }
}
