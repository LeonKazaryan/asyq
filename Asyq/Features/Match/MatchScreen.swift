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
                FlickSurface { strength, tilt in controller.spin(strength: strength, tilt: tilt) }
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
