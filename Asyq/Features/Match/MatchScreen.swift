import SwiftUI

/// A «Бес табан» match against the rival.
struct MatchScreen: View {
    @State private var controller: MatchController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onClose: () -> Void

    init(category: AgeCategory, onClose: @escaping () -> Void) {
        _controller = State(initialValue: MatchController(category: category, seed: DebugLaunchArguments.seed ?? UInt64.random(in: 1...UInt64.max)))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            ArenaView(stage: controller.stage)
                .id(ObjectIdentifier(controller))
                .ignoresSafeArea()
            ArenaVignette()
            if controller.canSpin {
                IiruSurface(controller: controller)
            } else {
                SlingshotSurface(stage: controller.stage)
            }
            MatchHUD(controller: controller, onClose: close, onRematch: rematch)
            #if DEBUG
            FrameRateBadge(stage: controller.stage)
            #endif
        }
        .statusBarHidden()
        .defersSystemGestures(on: .bottom)
        .onAppear { controller.stage.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in controller.stage.reduceMotion = newValue }
    }

    private func close() {
        controller.stop()
        onClose()
    }

    private func rematch() {
        controller.stop()
        controller = MatchController(category: controller.category)
        controller.stage.reduceMotion = reduceMotion
    }
}

/// Иіру: a quick flick anywhere spins the saqa; faster spins harder, the flick's lean tilts it.
private struct IiruSurface: View {
    let controller: MatchController

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
                        controller.spin(strength: Float(strength), tilt: Float(velocity.width / speed))
                    }
            )
    }
}
