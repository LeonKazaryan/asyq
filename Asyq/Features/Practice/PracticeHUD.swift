import SwiftUI

/// Over the practice arena: where you throw from, the score, the referee, the pull.
struct PracticeHUD: View {
    let controller: PracticeController
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let onClose {
                    GlassIconButton(systemName: "chevron.left", label: "Back", action: onClose)
                }
                SpotChip(spot: controller.spot, distance: controller.throwDistance)
                Spacer(minLength: 0)
                ScoreChip(knockedOut: controller.knockedOut, total: controller.category.keneiCount)
                GlassIconButton(systemName: "arrow.counterclockwise", label: "Start over") {
                    controller.restart()
                }
                .disabled(!controller.stage.canPull)
            }
            .padding(.top, 8)
            ZStack {
                if let banner = controller.banner {
                    RefereeBannerView(banner: banner)
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
            PullArea(stage: controller.stage, showsHint: controller.showsHint)
        }
        .padding(.horizontal, 16)
    }
}

/// Kenei knocked out so far.
private struct ScoreChip: View {
    let knockedOut: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            KeneiGlyph()
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

/// A tiny kenei for counters.
struct KeneiGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(Palette.bone.color)
            .frame(width: 14, height: 10)
            .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(Palette.ink.color.opacity(0.15), lineWidth: 0.5))
    }
}
