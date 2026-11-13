import SwiftUI

/// Hosts the Metal arena in SwiftUI and hands its frames to the controller.
struct ArenaView: UIViewRepresentable {
    let controller: PracticeController

    func makeUIView(context: Context) -> ArenaMetalView {
        let view = ArenaMetalView(device: controller.metalDevice)
        view.onFrame = { [weak controller] deltaTime, layer in
            controller?.frame(deltaTime, layer: layer) ?? .none
        }
        view.onResize = { [weak controller] size in
            controller?.resize(to: size)
        }
        controller.wake = { [weak view] in view?.wake() }
        return view
    }

    func updateUIView(_ view: ArenaMetalView, context: Context) {}
}
