import AppKit
import QuartzCore
import TinypenCore

/// The laser, the spotlight and the zoom lens: drawn every frame while one is on, following the
/// pointer, and idle otherwise.
@MainActor
final class EffectsView: PassThroughView {
    private unowned let session: Session
    let displayID: CGDirectDisplayID
    private var link: CADisplayLink?
    private var trail = LaserTrail()
    private var pointer: CGPoint?
    let lens = CALayer()
    private let lensRing = CAShapeLayer()

    init(session: Session, displayID: CGDirectDisplayID) {
        self.session = session
        self.displayID = displayID
        super.init(frame: .zero)
        wantsLayer = true
        lens.masksToBounds = true
        lens.isHidden = true
        lens.backgroundColor = NSColor.windowBackgroundColor.cgColor
        lens.contentsGravity = .resize
        lens.magnificationFilter = .linear
        lensRing.fillColor = nil
        lensRing.strokeColor = NSColor.white.cgColor
        lensRing.lineWidth = 3
        lensRing.shadowOpacity = 0.4
        lensRing.shadowRadius = 6
        lensRing.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("EffectsView is created in code only")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let layer, lens.superlayer == nil else { return }
        layer.addSublayer(lens)
        layer.addSublayer(lensRing)
    }

    /// Runs the frame clock while an effect is on, and lets it stop when none is.
    func refresh() {
        let running = session.effect != nil
        if running, link == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !running, let link {
            link.invalidate()
            self.link = nil
            trail = LaserTrail()
            pointer = nil
        }
        if session.effect != .zoom {
            lens.isHidden = true
            lensRing.isHidden = true
        }
        needsDisplay = true
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let overlay = session.overlay(for: displayID)
        let point = overlay?.pointer()
        if session.effect == .laser, let point, point != pointer { trail.add(point, at: now) }
        trail.prune(at: now)
        let moved = point != pointer
        pointer = point
        if session.effect == .zoom { placeLens() }
        if moved || !trail.isIdle(at: now) { needsDisplay = true }
        if let point { session.pointer(isOn: displayID, at: point) }
    }

    /// The lens on the pointer, showing the latest frame of this display magnified.
    private func placeLens() {
        guard let pointer, session.zoomDisplay == displayID, let frame = session.zoomFrame else {
            lens.isHidden = true
            lensRing.isHidden = true
            return
        }
        let radius = Lens.radius
        let box = CGRect(x: pointer.x - radius, y: pointer.y - radius, width: radius * 2, height: radius * 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lens.isHidden = false
        lensRing.isHidden = false
        lens.frame = box
        lens.cornerRadius = radius
        lens.contents = frame
        let source = Lens.source(center: pointer, radius: radius, magnification: session.magnification)
        let size = bounds.size
        // Unit coordinates of the frame; the layer is flipped with its view, so y counts down.
        lens.contentsRect = CGRect(x: source.minX / size.width, y: source.minY / size.height,
                                   width: source.width / size.width, height: source.height / size.height)
        lensRing.path = CGPath(ellipseIn: box, transform: nil)
        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        switch session.effect {
        case .spotlight: drawSpotlight(in: context)
        case .laser: drawLaser(in: context)
        default: break
        }
    }

    /// Everything dimmed but a circle round the pointer; a display without the pointer is dimmed
    /// whole, so the eye goes to the one that has it.
    private func drawSpotlight(in context: CGContext) {
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.addRect(bounds)
        if let pointer {
            let radius = session.spotlightRadius
            context.addEllipse(in: CGRect(x: pointer.x - radius, y: pointer.y - radius, width: radius * 2, height: radius * 2))
        }
        context.fillPath(using: .evenOdd)
    }

    /// A red glow on the pointer, and its trail fading out behind it.
    private func drawLaser(in context: CGContext) {
        let red = NSColor(srgbRed: 1, green: 0.16, blue: 0.12, alpha: 1)
        let points = trail.visible(at: CACurrentMediaTime())
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 10, color: red.cgColor)
        for (index, pair) in zip(points, points.dropFirst()).enumerated() {
            let fade = pair.1.alpha
            context.setStrokeColor(red.withAlphaComponent(fade).cgColor)
            context.setLineWidth(2 + 4 * fade * CGFloat(index + 1) / CGFloat(max(points.count, 1)))
            context.move(to: pair.0.point)
            context.addLine(to: pair.1.point)
            context.strokePath()
        }
        guard let pointer else { return }
        context.setFillColor(red.cgColor)
        context.fillEllipse(in: CGRect(x: pointer.x - 8, y: pointer.y - 8, width: 16, height: 16))
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.fillEllipse(in: CGRect(x: pointer.x - 3, y: pointer.y - 3, width: 6, height: 6))
    }
}
