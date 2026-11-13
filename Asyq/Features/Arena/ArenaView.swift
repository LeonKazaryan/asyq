import SwiftUI

/// Hosts the Metal arena in SwiftUI and hands its frames to the stage.
struct ArenaView: UIViewRepresentable {
    let stage: ArenaStage

    func makeUIView(context: Context) -> ArenaMetalView {
        let view = ArenaMetalView(device: stage.metalDevice)
        view.onFrame = { [weak stage] deltaTime, layer in
            stage?.frame(deltaTime, layer: layer) ?? .none
        }
        view.onResize = { [weak stage] size in
            stage?.resize(to: size)
        }
        stage.wake = { [weak view] in view?.wake() }
        return view
    }

    func updateUIView(_ view: ArenaMetalView, context: Context) {}
}
