import SwiftUI

/// Free throwing at the kon.
struct PracticeScreen: View {
    @State private var controller: PracticeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onClose: (() -> Void)?

    init(category: AgeCategory, onClose: (() -> Void)? = nil) {
        _controller = State(initialValue: PracticeController(category: category))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            ArenaView(stage: controller.stage)
                .ignoresSafeArea()
            ArenaVignette()
            SlingshotSurface(stage: controller.stage)
            PracticeHUD(controller: controller, onClose: onClose)
            #if DEBUG
            FrameRateBadge(stage: controller.stage)
            #endif
        }
        .statusBarHidden()
        // Pulling down near the bottom edge mustn't fling the app away.
        .defersSystemGestures(on: .bottom)
        .onAppear { controller.stage.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in controller.stage.reduceMotion = newValue }
    }
}

#Preview {
    PracticeScreen(category: .eresek)
}
