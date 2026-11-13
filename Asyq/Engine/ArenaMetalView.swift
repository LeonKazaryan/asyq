import Metal
import QuartzCore
import UIKit

/// How often the arena needs drawing, judged after every frame.
enum FrameDemand {
    /// Something moves: as fast as the screen goes, up to 120 Hz.
    case full
    /// At rest: no frames at all, the last one stays on screen until `wake()`.
    case none
}

/// The arena's drawing surface: a Metal layer plus a display link asking for up to 120 Hz.
/// Every frame it reports the time step, and `onFrame` advances the game, draws and says
/// whether another frame is needed. A still scene costs no power. Ported from Nomaded's
/// `GlobeMetalView`.
final class ArenaMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    // The layer class above guarantees the cast.
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onFrame: (@MainActor (TimeInterval, CAMetalLayer) -> FrameDemand)?
    /// The size in points.
    var onResize: (@MainActor (CGSize) -> Void)?
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if !isPaused { demand = .full }
            applyDemand()
        }
    }

    private var displayLink: CADisplayLink?
    private var lastTargetTimestamp: CFTimeInterval?
    private var demand = FrameDemand.full

    init(device: MTLDevice?) {
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = ArenaRenderer.pixelFormat
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = true
        metalLayer.framebufferOnly = true
        backgroundColor = .black
        // The system may drop a background app's layer contents; redraw on the way back.
        NotificationCenter.default.addObserver(self, selector: #selector(wake), name: UIApplication.didBecomeActiveNotification, object: nil)
        if #available(iOS 27.0, *) {
            registerForTraitChanges([UITraitSystemPrefersReducedResourceUsage.self]) { (view: ArenaMetalView, _: UITraitCollection) in
                view.applyDemand()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Draws again after the scene came to rest. Cheap: call it on any change.
    @objc func wake() {
        guard demand != .full else { return }
        demand = .full
        applyDemand()
    }

    private func applyDemand() {
        guard let displayLink else { return }
        let stops = isPaused || demand == .none
        // Don't count the time without frames as one huge step.
        if stops || displayLink.isPaused { lastTargetTimestamp = nil }
        displayLink.isPaused = stops
        displayLink.preferredFrameRateRange = prefersReducedResources
            ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    }

    /// The system asks apps to go easy (iOS 27): hot, or saving power. 60 frames instead of 120.
    private var prefersReducedResources: Bool {
        if #available(iOS 27.0, *) {
            traitCollection.systemPrefersReducedResourceUsage
        } else {
            false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        onResize?(bounds.size)
        guard size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        wake()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        lastTargetTimestamp = nil
        // Off screen there's nothing to draw. Dropping the link also lets go of `self`,
        // which the link holds as its target.
        guard let window else { return }
        let link = makeDisplayLink(in: window)
        link.add(to: .main, forMode: .common)
        displayLink = link
        demand = .full
        applyDemand()
    }

    /// The scene's own link where there is one (iOS 27): it follows the scene from display to display.
    private func makeDisplayLink(in window: UIWindow) -> CADisplayLink {
        if #available(iOS 27.0, *), let link = window.windowScene?.displayLink(target: self, selector: #selector(step)) {
            return link
        }
        return CADisplayLink(target: self, selector: #selector(step))
    }

    @objc private func step(_ link: CADisplayLink) {
        guard window?.windowScene?.activationState != .background else {
            lastTargetTimestamp = nil
            return
        }
        // Step to the time this frame will be on screen, so motion stays even when the rate
        // changes between 60 and 120; never let time run backwards.
        let target = link.targetTimestamp
        let deltaTime = lastTargetTimestamp.map { max(0, target - $0) } ?? link.duration
        lastTargetTimestamp = max(target, lastTargetTimestamp ?? target)
        let next = onFrame?(deltaTime, metalLayer) ?? .none
        guard next != demand else { return }
        demand = next
        applyDemand()
    }
}
