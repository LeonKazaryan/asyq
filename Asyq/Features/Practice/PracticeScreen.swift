import SwiftUI

/// M1: throw at the kon. The arena fills the screen; the slingshot works anywhere below the
/// top bar; the HUD floats on glass.
struct PracticeScreen: View {
    @State private var controller = PracticeController(category: DebugLaunchArguments.category ?? .eresek)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ArenaView(controller: controller)
                .ignoresSafeArea()
            vignette
            slingshotSurface
            PracticeHUD(controller: controller)
        }
        .statusBarHidden()
        // Pulling down near the bottom edge mustn't fling the app away.
        .defersSystemGestures(on: .bottom)
        .onAppear { controller.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in controller.reduceMotion = newValue }
    }

    /// Darkens the corners a touch, like a lens: keeps the eye on the kon.
    private var vignette: some View {
        RadialGradient(
            colors: [.clear, Palette.ink.color.opacity(0.18)],
            center: .center,
            startRadius: 180,
            endRadius: 620
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var slingshotSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if controller.pullPower == nil {
                            controller.beginPull(at: value.startLocation)
                        }
                        controller.updatePull(to: value.location)
                    }
                    .onEnded { value in
                        controller.endPull(velocity: CGVector(dx: value.velocity.width, dy: value.velocity.height))
                    }
            )
    }
}

#Preview {
    PracticeScreen()
}
