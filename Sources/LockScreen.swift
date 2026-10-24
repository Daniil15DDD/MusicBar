import AppKit
import Combine
import CoreImage
import CoreText

/// A view that reports clicks; works on the first click even though the lock screen window is never active.
class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Button that visibly presses in while held and springs back on release.
final class PressButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        animateScale(to: 0.82, spring: false)
        super.mouseDown(with: event)   // returns on mouse up; the action has fired by then
        animateScale(to: 1)
    }
}

extension CAMediaTimingFunction {
    /// Things arriving start fast and settle gently; things leaving are the mirror image (slow start, quick finish).
    static let arrive = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    static let leave = CAMediaTimingFunction(controlPoints: 0.64, 0, 0.78, 0)
}

extension NSView {
    /// A scale transform about the view's CENTRE, whatever the layer's anchor point is (AppKit keeps resetting it,
    /// which made scale animations pivot around the bottom-left corner).
    func scaled(_ s: CGFloat) -> CATransform3D {
        guard let l = layer else { return CATransform3DIdentity }
        let a = l.anchorPoint, b = l.bounds
        let c = CGPoint(x: b.width * (0.5 - a.x), y: b.height * (0.5 - a.y))
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(c.x, c.y, 0), s, s, 1), -c.x, -c.y, 0)
    }

    /// One-shot "press" feedback: dip and spring back (around the centre).
    func pulse(_ to: CGFloat = 0.86) {
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [NSValue(caTransform3D: CATransform3DIdentity), NSValue(caTransform3D: scaled(to)), NSValue(caTransform3D: CATransform3DIdentity)]
        a.keyTimes = [0, 0.35, 1]
        a.duration = 0.28
        a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        layer?.add(a, forKey: "pulse")
    }

    /// Animates the view's scale to `s` (about its centre) and leaves it there: a spring, or a quick ease for the press-down.
    func animateScale(to s: CGFloat, spring: Bool = true, from start: CGFloat? = nil) {
        guard let l = layer else { return }
        // always start from what is on screen right now, so a half-finished animation can be redirected without a jump
        let from = start.map { scaled($0) } ?? l.presentation()?.transform ?? l.transform
        let to = scaled(s)
        l.transform = to
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
        if spring {
            let a = CASpringAnimation(keyPath: "transform")
            a.fromValue = NSValue(caTransform3D: from); a.toValue = NSValue(caTransform3D: to)
            a.damping = 30; a.stiffness = 322; a.mass = 1   // response 0.35s, damping ratio 0.85: settles smoothly, the faintest overshoot
            a.duration = a.settlingDuration
            l.add(a, forKey: "scale")
        } else {
            let a = CABasicAnimation(keyPath: "transform")
            a.fromValue = NSValue(caTransform3D: from); a.toValue = NSValue(caTransform3D: to)
            a.duration = 0.1
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            l.add(a, forKey: "scale")
        }
    }

    /// Fades this view in from invisible to `target` with an explicit layer animation.
    func fadeIn(to target: CGFloat, duration: CFTimeInterval) {
        alphaValue = target
        guard let l = layer else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0; a.toValue = target; a.duration = duration
        a.timingFunction = .arrive
        l.add(a, forKey: "fadeIn")
    }

    /// Fades this view from its current opacity to invisible with an explicit layer animation.
    func fadeOut(duration: CFTimeInterval) {
        guard let l = layer else { alphaValue = 0; return }
        let from = l.presentation()?.opacity ?? l.opacity
        alphaValue = 0
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from; a.toValue = 0; a.duration = duration
        a.timingFunction = .leave
        l.add(a, forKey: "fadeOut")
    }

    func crossfade(_ d: CFTimeInterval = 0.25) {
        let t = CATransition(); t.type = .fade; t.duration = d
        layer?.add(t, forKey: "crossfade")
    }
}

/// Our own "liquid glass": a light blur of what is behind the card (the system backdrop layer Apple's own panels use, with a
/// small radius we choose), a faint white tint, a bright edge that fades round the card and a soft shine across the top.
/// Apple's NSGlassEffectView only blurs heavily with a tint when hosted in a window like ours, so it looked flat grey.
/// shortcut: uses the private CABackdropLayer / CAFilter classes; if they are missing it falls back to a plain translucent tint.
final class GlassBackground: NSView {
    private let radius: CGFloat
    private var backdrop: CALayer?
    private let tint = CALayer()
    private let shine = CAGradientLayer()
    private let edge = CAGradientLayer()
    private let edgeMask = CAShapeLayer()

    /// `tint` and `blur` default to the very clear lock screen card; the player menu passes a darker tint and a bit more blur for legibility.
    init(frame: NSRect, radius: CGFloat, tint tintColor: NSColor? = nil, blur: CGFloat = 0.9) {
        self.radius = radius
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true

        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type, let fcls = NSClassFromString("CAFilter") as? NSObject.Type {
            func filter(_ type: String, _ key: String, _ value: Any) -> NSObject? {
                guard let f = fcls.perform(NSSelectorFromString("filterWithType:"), with: type)?.takeUnretainedValue() as? NSObject else { return nil }
                f.setValue(value, forKey: key)
                return f
            }
            let b = cls.init()
            b.setValue(true, forKey: "windowServerAware")
            b.setValue(UUID().uuidString, forKey: "groupName")
            b.setValue(1.0, forKey: "scale")
            b.filters = [filter("gaussianBlur", "inputRadius", blur), filter("colorSaturate", "inputAmount", 1.15)].compactMap { $0 }
            layer?.addSublayer(b)
            backdrop = b
        }
        tint.backgroundColor = (tintColor ?? NSColor.white.withAlphaComponent(backdrop == nil ? 0.05 : 0.012)).cgColor
        layer?.addSublayer(tint)

        shine.colors = [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        shine.startPoint = CGPoint(x: 0.5, y: 1); shine.endPoint = CGPoint(x: 0.5, y: 0.55)   // top of the card is y = 1
        layer?.addSublayer(shine)

        edge.colors = [NSColor.white.withAlphaComponent(0.75).cgColor, NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0.35).cgColor]
        edge.startPoint = CGPoint(x: 0, y: 1); edge.endPoint = CGPoint(x: 1, y: 0)
        edgeMask.fillColor = nil; edgeMask.strokeColor = NSColor.white.cgColor; edgeMask.lineWidth = 1.4
        edge.mask = edgeMask
        layer?.addSublayer(edge)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Changes how milky the glass is (clear = no tint) without rebuilding it.
    func setTint(_ color: NSColor) { tint.backgroundColor = color.cgColor }

    private var snap: CALayer?
    private static let ci = CIContext()

    /// README images only: the live blur layer can't render offscreen (it comes out white), so a picture of what lies behind the glass
    /// (see glassCrop) takes its place; the tint, the shine and the bright edge stay on top.
    func setScreenshotBackdrop(_ img: CGImage?) {
        backdrop?.isHidden = true
        snap?.removeFromSuperlayer(); snap = nil
        guard let img else { tint.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor; return }
        let l = CALayer()
        l.contents = img
        l.contentsGravity = .resizeAspectFill
        layer?.insertSublayer(l, at: 0)
        snap = l
        needsLayout = true   // the tint stays at the live glass's own (almost invisible) value
    }

    /// The part of `full` (the whole picture, bottom-left origin, `scale` pixels per point) under `rect`, with the same two filters the live
    /// glass uses (a 0.9 gaussian blur and a 1.15 saturation boost), so the README card matches the real one: almost perfectly clear.
    static func glassCrop(_ full: CGImage, rect: NSRect, scale: CGFloat) -> CGImage? {
        let img = CIImage(cgImage: full)
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let blur = CIFilter(name: "CIGaussianBlur"), let color = CIFilter(name: "CIColorControls") else { return nil }
        blur.setValue(img.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(0.9 * scale, forKey: kCIInputRadiusKey)
        guard let soft = blur.outputImage else { return nil }
        color.setValue(soft, forKey: kCIInputImageKey)
        color.setValue(1.15, forKey: kCIInputSaturationKey)
        guard let out = color.outputImage?.cropped(to: crop) else { return nil }
        return ci.createCGImage(out, from: crop)
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        [backdrop, snap, tint, shine, edge].compactMap { $0 }.forEach { $0.frame = bounds }
        edgeMask.frame = bounds
        edgeMask.path = CGPath(roundedRect: bounds.insetBy(dx: 0.7, dy: 0.7), cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }
}

/// Progress bar you can click or drag to seek. Thickens while dragging; the seek is sent on release.
final class SeekBarView: NSView {
    private let track = NSView(), fill = NSView()
    private var barH: CGFloat = 4
    private(set) var progress: CGFloat = 0
    private(set) var dragging = false
    var onScrub: ((CGFloat) -> Void)?
    var onSeek: ((CGFloat) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for (v, a) in [(track, 0.22), (fill, 0.9)] {
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.white.withAlphaComponent(CGFloat(a)).cgColor
            addSubview(v)
        }
        applyHeight(4, animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func frames(_ h: CGFloat) -> (NSRect, NSRect) {
        let y = (bounds.height - h) / 2
        return (NSRect(x: 0, y: y, width: bounds.width, height: h), NSRect(x: 0, y: y, width: bounds.width * progress, height: h))
    }

    private var heightToken = 0
    private var animatingHeight = false

    private func applyHeight(_ h: CGFloat, animated: Bool) {
        barH = h
        let (tf, ff) = frames(h)
        track.layer?.cornerRadius = h / 2
        fill.layer?.cornerRadius = h / 2
        heightToken += 1
        let token = heightToken
        if animated {
            animatingHeight = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)   // same timing for both, so they move together
                self.track.animator().frame = tf
                self.fill.animator().frame = ff
            }, completionHandler: { [weak self] in
                guard let self, self.heightToken == token else { return }
                self.animatingHeight = false
                let (t2, f2) = self.frames(self.barH)   // catch up with any progress that arrived meanwhile
                self.track.frame = t2; self.fill.frame = f2
            })
        } else { animatingHeight = false; track.frame = tf; fill.frame = ff }
    }

    func setProgress(_ p: CGFloat, animated: Bool) {
        progress = min(max(p, 0), 1)
        // While the thickness animation runs it owns both frames; a second animation on the fill would make the
        // white part finish at a different time than the dark track. It catches up when the animation ends.
        guard !animatingHeight else { return }
        let ff = frames(barH).1
        if animated {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; $0.timingFunction = CAMediaTimingFunction(name: .linear); self.fill.animator().frame = ff }
        } else { fill.frame = ff }
    }

    private func fraction(_ e: NSEvent) -> CGFloat { min(max(convert(e.locationInWindow, from: nil).x / max(bounds.width, 1), 0), 1) }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        progress = fraction(event)
        applyHeight(8, animated: true)
        onScrub?(progress)
    }
    override func mouseDragged(with event: NSEvent) { setProgress(fraction(event), animated: false); onScrub?(progress) }
    override func mouseUp(with event: NSEvent) {
        progress = fraction(event)   // set the value first, then let applyHeight animate track AND fill together
        dragging = false
        applyHeight(4, animated: true)
        onSeek?(progress)
    }
}

/// Five bars that ease to new random heights while playing (Boring-Notch style) and shrink to five still dots when paused.
final class WaveBarsView: NSView {
    private var bars: [CALayer] = []
    private var maxH: CGFloat = 14
    private let w: CGFloat = 2.5, gap: CGFloat = 2
    /// Each bar has its own rhythm: a period and a loop of heights (fractions of the full height). Different periods mean the
    /// bars never line up, which is what makes the motion read as organic instead of mechanical. It runs on the compositor.
    private let rhythm: [(period: CFTimeInterval, heights: [CGFloat])] = [
        (1.30, [0.40, 0.85, 0.55, 0.95, 0.35]),
        (1.05, [0.65, 0.30, 0.90, 0.45, 0.75]),
        (1.55, [0.90, 0.50, 1.00, 0.35, 0.70]),
        (1.15, [0.35, 0.80, 0.45, 0.90, 0.60]),
        (1.40, [0.70, 0.40, 0.85, 0.30, 0.95]),
    ]
    /// Menu bar / popover: follow the system text colour (light or dark). Lock screen: always white.
    var adaptiveColor = false { didSet { applyColor() } }
    var animating = false { didSet { if animating != oldValue { apply() } } }

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        let changed = maxH != bounds.height
        maxH = bounds.height
        if bars.isEmpty {
            for _ in 0..<5 {
                let l = CALayer()
                l.cornerRadius = w / 2
                l.bounds = CGRect(x: 0, y: 0, width: w, height: w)
                l.opacity = 0.55
                layer?.addSublayer(l)
                bars.append(l)
            }
            applyColor()
            apply()
        } else if changed { apply() }
        var x = (bounds.width - (5 * w + 4 * gap)) / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in bars { l.position = CGPoint(x: x + w / 2, y: bounds.midY); x += w + gap }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyColor() }

    private func applyColor() {
        let c: NSColor = adaptiveColor ? .labelColor : .white
        effectiveAppearance.performAsCurrentDrawingAppearance { bars.forEach { $0.backgroundColor = c.cgColor } }
    }

    /// Playing: every bar loops through its own smooth curve. Stopping: each bar eases down from wherever it is (never jumps) to a dot.
    private func apply() {
        guard !bars.isEmpty else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (i, l) in bars.enumerated() {
            let from = l.presentation()?.bounds.height ?? l.bounds.height
            l.removeAnimation(forKey: "wave"); l.removeAnimation(forKey: "settle")
            if animating {
                let r = rhythm[i]
                let values = (r.heights + [r.heights[0]]).map { max($0 * maxH, self.w) }
                l.bounds = CGRect(x: 0, y: 0, width: w, height: values[0])
                if !reduce {
                    let a = CAKeyframeAnimation(keyPath: "bounds.size.height")
                    a.values = values
                    a.calculationMode = .cubic          // a smooth curve through the points, no corners
                    a.duration = r.period
                    a.repeatCount = .infinity
                    l.add(a, forKey: "wave")
                }
                fade(l, to: 0.95)
            } else {
                l.bounds = CGRect(x: 0, y: 0, width: w, height: w)
                if !reduce, from > w {
                    let a = CASpringAnimation(keyPath: "bounds.size.height")
                    a.fromValue = from; a.toValue = w
                    a.mass = 1; a.stiffness = 200; a.damping = 28   // critically damped: no bounce, just a soft landing
                    a.duration = a.settlingDuration
                    l.add(a, forKey: "settle")
                }
                fade(l, to: 0.55)
            }
        }
    }

    private func fade(_ l: CALayer, to o: Float) {
        let from = l.presentation()?.opacity ?? l.opacity
        l.opacity = o
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from; a.toValue = o; a.duration = 0.4; a.timingFunction = .arrive
        l.add(a, forKey: "fade")
    }
}

/// Now Playing card for the lock screen, built from plain AppKit views (a SwiftUI one vanished there).
/// Cover + title/artist + waveform on top, progress row, then previous / play / next. Paused: cover dimmed, waveform as dots.
final class LockCardView: NSView {
    static let size = NSSize(width: 330, height: 135)
    var onCoverTap: (() -> Void)?
    private let media: MediaController
    private let glass = NSVisualEffectView()   // frosted look (default)
    private let tint = NSView()
    private var liquid: NSView?                // real Liquid Glass (macOS 26+), chosen in settings
    private let cover = ClickView()
    private let titleL = NSTextField(labelWithString: "")
    private let artistL = NSTextField(labelWithString: "")
    private let seek = SeekBarView(frame: NSRect(x: 54, y: 46, width: 222, height: 16))   // taller than the 4pt bar: easy to hit
    private let elapsedL = NSTextField(labelWithString: "0:00"), remainL = NSTextField(labelWithString: "-0:00")
    private let prevB = PressButton(), playB = PressButton(), nextB = PressButton()
    private let shuffleB = PressButton(), repeatB = PressButton()
    private let favB = PressButton()   // Apple Music star
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastPlaying: Bool?
    private var fullscreen = false
    private var lastFav: Bool?
    private weak var lastArt: NSImage?

    init(media: MediaController) {
        self.media = media
        super.init(frame: NSRect(origin: .zero, size: LockCardView.size))
        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        glass.frame = bounds
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 26
        glass.layer?.masksToBounds = true
        tint.frame = bounds
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        tint.layer?.cornerRadius = 26
        liquid = GlassBackground(frame: bounds, radius: 26)

        // Layout (origin bottom-left): cover top-left; progress row and controls sit below it with clear gaps.
        cover.frame = NSRect(x: 16, y: 69, width: 52, height: 52)
        cover.wantsLayer = true
        cover.layer?.cornerRadius = 12
        cover.layer?.masksToBounds = true
        cover.layer?.contentsGravity = .resizeAspectFill
        cover.layer?.backgroundColor = NSColor.darkGray.cgColor
        cover.onClick = { [weak self] in guard let self, !self.fullscreen else { return }; self.cover.pulse(0.92); self.onCoverTap?() }

        style(titleL, size: 14, weight: .bold, color: .white, frame: NSRect(x: 80, y: 100, width: 200, height: 18))
        style(artistL, size: 12, weight: .regular, color: NSColor.white.withAlphaComponent(0.65), frame: NSRect(x: 80, y: 82, width: 200, height: 16))

        seek.onScrub = { [weak self] f in self?.scrub(f) }
        seek.onSeek = { [weak self] f in self?.commitSeek(f) }
        for l in [elapsedL, remainL] {
            l.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            l.textColor = NSColor.white.withAlphaComponent(0.7)
        }
        elapsedL.frame = NSRect(x: 14, y: 48, width: 38, height: 12)
        remainL.frame = NSRect(x: 278, y: 48, width: 38, height: 12)
        remainL.alignment = .right

        // one row, centred on x=165: shuffle, previous, play, next, repeat
        button(shuffleB, "shuffle", 15, NSRect(x: 52, y: 6, width: 36, height: 36), #selector(shuffle))
        button(prevB, "backward.fill", 18, NSRect(x: 98, y: 4, width: 40, height: 40), #selector(prev))
        button(playB, "play.fill", 26, NSRect(x: 145, y: 2, width: 40, height: 44), #selector(togglePlay))
        button(nextB, "forward.fill", 18, NSRect(x: 192, y: 4, width: 40, height: 40), #selector(next))
        button(repeatB, "repeat", 15, NSRect(x: 242, y: 6, width: 36, height: 36), #selector(repeatTap))
        button(favB, "star", 16, NSRect(x: 290, y: 97, width: 28, height: 24), #selector(favourite))   // top right, level with the title

        ([glass, tint, liquid].compactMap { $0 } + [cover, titleL, artistL, seek, elapsedL, remainL, shuffleB, prevB, playB, nextB, repeatB, favB]).forEach(addSubview)

        Publishers.Merge3(media.$info.map { _ in () }, media.$artwork.map { _ in () }, media.$motionURL.map { _ in () })
            .receive(on: DispatchQueue.main)   // @Published fires before the value changes; hop so we read the new one
            .sink { [weak self] in self?.refresh() }
            .store(in: &bag)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func style(_ l: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor, frame: NSRect) {
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        l.frame = frame
    }

    private func button(_ b: NSButton, _ symbol: String, _ size: CGFloat, _ frame: NSRect, _ action: Selector) {
        b.frame = frame
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = .white
        b.target = self
        b.action = action
        b.wantsLayer = true
        setSymbol(b, symbol, size)
    }

    private func setSymbol(_ b: NSButton, _ name: String, _ size: CGFloat) {
        b.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
    }

    @objc private func prev() { media.previous() }
    @objc private func next() { media.next() }
    @objc private func togglePlay() { media.togglePlayPause() }
    @objc private func shuffle() { media.toggleShuffle() }
    @objc private func repeatTap() { media.cycleRepeat() }
    @objc private func favourite() { favB.pulse(1.3); media.toggleFavorite() }   // soft pop

    /// For the README images only: the glass blur can't render offscreen (it comes out white), so use a flat dark background.
    func useFlatBackgroundForScreenshots(fullscreen on: Bool, snapshot: CGImage? = nil) {
        if on { fullscreen = true; layoutTexts(animated: false); cover.alphaValue = 0 }   // small cover away, text slid left, instantly
        glass.isHidden = true
        tint.isHidden = true
        liquid?.isHidden = false
        (liquid as? GlassBackground)?.setScreenshotBackdrop(snapshot.flatMap { GlassBackground.glassCrop($0, rect: frame, scale: 2) })
        layer?.borderWidth = 0
        applyTextShadow(true)
    }

    /// A very clear card needs a soft dark shadow behind the text and controls to stay readable on bright wallpapers.
    private func applyTextShadow(_ on: Bool) {
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.45); sh.shadowBlurRadius = 5; sh.shadowOffset = .zero
        [titleL, artistL, elapsedL, remainL, shuffleB, prevB, playB, nextB, repeatB, favB].forEach { $0.shadow = on ? sh : nil }
    }

    /// Frosted glass (default) or real Liquid Glass, per the setting.
    private func applyStyle() {
        let useLiquid = liquid != nil && (UserDefaults.standard.object(forKey: "lockLiquidGlass") as? Bool ?? true)   // Liquid Glass unless switched off
        liquid?.isHidden = !useLiquid
        glass.isHidden = useLiquid
        tint.isHidden = useLiquid
        layer?.borderWidth = useLiquid ? 0 : 1
        // a very clear card needs a soft dark shadow behind the text and controls to stay readable on bright wallpapers
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.45); sh.shadowBlurRadius = 5; sh.shadowOffset = .zero
        [titleL, artistL, elapsedL, remainL, shuffleB, prevB, playB, nextB, repeatB, favB].forEach { $0.shadow = useLiquid ? sh : nil }
    }

    /// In fullscreen the big cover is already on screen: the small cover shrinks away and the text slides left into its place.
    func setFullscreen(_ on: Bool) {
        fullscreen = on
        layoutTexts(animated: true)
        applyCover()
    }

    private var coverScale: CGFloat { fullscreen ? 0.6 : (lastPlaying == false ? 0.88 : 1) }
    private var coverAlpha: CGFloat { fullscreen ? 0 : (lastPlaying == false ? 0.62 : 1) }

    private func applyCover() {
        cover.animateScale(to: coverScale)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; $0.timingFunction = .arrive; self.cover.animator().alphaValue = self.coverAlpha }
    }

    private func layoutTexts(animated: Bool) {
        let x: CGFloat = fullscreen ? 16 : 80, w: CGFloat = fullscreen ? 264 : 200
        let tf = NSRect(x: x, y: 100, width: w, height: 18), af = NSRect(x: x, y: 82, width: w, height: 16)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                ctx.timingFunction = .arrive   // a long gentle settle instead of a symmetric ease
                self.titleL.animator().frame = tf
                self.artistL.animator().frame = af
            }
        } else { titleL.frame = tf; artistL.frame = af }
    }

    func setActive(_ on: Bool) {
        timer?.invalidate(); timer = nil
        lastPlaying = nil
        if on {
            lastFav = nil
            applyStyle()
            fullscreen = false
            layoutTexts(animated: false)
            cover.layer?.removeAllAnimations()
            cover.layer?.transform = CATransform3DIdentity
            cover.alphaValue = 1
            isHidden = false
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = 0.45; $0.timingFunction = .arrive; self.animator().alphaValue = 1 }
            animateScale(to: 1, from: 0.96)   // the card arrives: it rises into place as it fades in
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else {
            isHidden = true
            alphaValue = 1
        }
    }

    private func refresh() {
        guard !isHidden else { return }
        let i = media.info
        let playing = i?.isPlaying == true
        titleL.stringValue = i?.title ?? "Not Playing"
        // If a running player was refused (Automation permission) and nothing is playing, say what to do instead of showing nothing.
        let hint = media.deniedPlayer.flatMap { i?.isPlaying == true ? nil : "Allow ORBT to control \($0): Settings → Privacy → Automation" }
        artistL.stringValue = hint ?? i?.artist ?? ""
        // shuffle / repeat: bright when on, dim when off; repeat shows "1" for repeat-one
        let repeatMode = i?.repeatMode ?? "off"
        shuffleB.contentTintColor = NSColor.white.withAlphaComponent(i?.shuffle == true ? 1 : 0.45)
        setSymbol(repeatB, repeatMode == "one" ? "repeat.1" : "repeat", 15)
        repeatB.contentTintColor = NSColor.white.withAlphaComponent(repeatMode != "off" ? 1 : 0.45)
        // favourite star: Apple Music only (Spotify's scripting has no like command), so it is hidden for Spotify
        // Apple Music: the star. Spotify (when connected in the settings): the plus that becomes a green tick, like Spotify's own app.
        let spotify = i?.player == .spotify
        favB.isHidden = !(i?.player == .music || (spotify && SpotifyAuth.shared.connected))
        let fav = i?.favorited == true
        if fav != lastFav { if lastFav != nil { favB.crossfade(0.18) }; lastFav = fav }   // outline <-> filled fades
        setSymbol(favB, spotify ? (fav ? "checkmark.circle.fill" : "plus.circle") : (fav ? "star.fill" : "star"), 15)
        favB.contentTintColor = spotify && fav ? NSColor(srgbRed: 0.114, green: 0.725, blue: 0.329, alpha: 1) : NSColor.white.withAlphaComponent(fav ? 1 : 0.6)
        if lastPlaying != playing {
            let animated = lastPlaying != nil
            lastPlaying = playing
            if animated { playB.crossfade(0.18) }
            setSymbol(playB, playing ? "pause.fill" : "play.fill", 26)
            applyCover()   // paused: a little faded and smaller (not darker); springs back on play
        }
        if media.artwork !== lastArt {
            if lastArt != nil { cover.crossfade(0.3) }
            lastArt = media.artwork
            cover.layer?.contents = media.artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        media.loadMotionIfNeeded()   // look the moving artwork up now, so fullscreen has it ready
        tick()
    }

    private func tick() {
        guard let i = media.info else { seek.setProgress(0, animated: false); return }
        guard !seek.dragging else { return }   // the finger decides while dragging
        let dur = max(i.duration, 0.001)
        let pos = min(i.position + (i.isPlaying ? Date().timeIntervalSince(media.sampleDate) : 0), dur)
        seek.setProgress(CGFloat(pos / dur), animated: true)
        elapsedL.stringValue = fmt(pos)
        remainL.stringValue = "-" + fmt(max(dur - pos, 0))
    }

    /// While dragging: show the time under the finger.
    private func scrub(_ f: CGFloat) {
        let dur = media.info?.duration ?? 0
        elapsedL.stringValue = fmt(Double(f) * dur)
        remainL.stringValue = "-" + fmt(max(dur - Double(f) * dur, 0))
    }

    /// On release: jump to that point in the song.
    private func commitSeek(_ f: CGFloat) {
        guard let dur = media.info?.duration, dur > 0 else { return }
        media.seek(to: Double(f) * dur)
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// The song's colour for the lock screen UI: its most distinct colour mixed into white, so the text isn't plain white.
enum SongTint {
    /// What lists (lyrics, queue) draw their text with; updated by the full-screen view.
    static var ink = NSColor.white
    private static var cache: (art: NSImage, accent: NSColor?)?

    /// A vivid version of the cover's most distinct colour (nil for a grey cover).
    static func accent(for art: NSImage?) -> NSColor? {
        guard let art else { return nil }
        if let c = cache, c.art === art { return c.accent }
        let a = art.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(LockBackdropView.accentColor)
        cache = (art, a)
        return a
    }
    /// White with the song's colour mixed in (plain white for a grey cover).
    static func white(for art: NSImage?) -> NSColor {
        accent(for: art).flatMap { NSColor.white.blended(withFraction: 0.35, of: $0) } ?? .white
    }
    /// A dark shade of the song's colour, for text on a bright picture (near-black for a grey cover).
    static func dark(for art: NSImage?) -> NSColor {
        guard let c = accent(for: art) else { return NSColor(white: 0.08, alpha: 1) }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: 0.27, alpha: 1)
    }
}

/// Full-screen backdrop shown when you click the cover on the card.
/// Moving artwork: the video fills the screen with a big serif clock. Otherwise: a blurred colour wash of the cover,
/// a large cover in the middle and a small clock at the top. We draw our own clock because this window covers the system one.
final class LockBackdropView: ClickView {
    private static let ci = CIContext()
    private let media: MediaController
    private let wash = NSView()
    private let shade = NSView()
    /// Sits above the video and the wash (but under the cover and the text) and darkens them when the picture is bright.
    private let scrim = NSView()
    private var artLuma: CGFloat = 0
    private var uiColor = NSColor.white
    private var darkUI = false
    private let video = LoopingPlayerView()
    private let big = NSView()
    private let bigShadow = NSView()
    private var lastPlaying: Bool?
    private let dateL = NSTextField(labelWithString: "")
    private let timeL = NSTextField(labelWithString: "")
    private let compactL = NSTextField(labelWithString: "")
    /// Liquid Glass behind the clock ("lockClockGlass"), and the editor a long press on the clock opens.
    private let clockGlass = GlassBackground(frame: .zero, radius: 28)
    private let editor = ClockEditorView(frame: .zero)
    private var editorOpen = false
    private var pressTimer: Timer?
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private weak var lastArt: NSImage?
    private var blurCache: (art: NSImage, image: CGImage?)?
    private var fadeToken = 0

    // Lyrics and queue: two buttons in the bottom-right corner swap the cover for a list on the right (cover and card slide left).
    enum Mode { case cover, lyrics, queue }
    private(set) var mode: Mode = .cover
    var onModeChange: ((Mode) -> Void)?
    private let lyricsView = LyricsView(frame: .zero)
    private let queueView = QueueView(frame: .zero)
    private let modePill = NSView()
    private let pillGlass = GlassBackground(frame: .zero, radius: 27, tint: NSColor.white.withAlphaComponent(0.08), blur: 5)
    private let lyricsB = PressButton(), queueB = PressButton()
    private let lyricsStore = LyricsStore()
    private var lyricsTimer: Timer?
    private var contentKey = ""
    private var showLyricsButton: Bool { UserDefaults.standard.object(forKey: "showLyricsButton") as? Bool ?? true }
    private var showQueueButton: Bool { UserDefaults.standard.object(forKey: "showQueueButton") as? Bool ?? true }
    /// Left edge of the cover (and the card under it) while a list is open.
    static func listColumnX(_ w: CGFloat) -> CGFloat { w * 0.12 }
    /// True while the Mac is locked: the moving artwork is looked up and its video buffered ahead of the click.
    var locked = false { didSet { if locked { warmUp() } } }

    init(media: MediaController, frame: NSRect) {
        self.media = media
        super.init(frame: frame)
        wantsLayer = true
        // no solid background: the fades must reveal / return to the user's wallpaper, not black
        for v in [wash, shade, scrim, big, bigShadow] { v.wantsLayer = true }
        scrim.layer?.backgroundColor = NSColor.black.cgColor
        scrim.alphaValue = 0
        wash.layer?.contentsGravity = .resizeAspectFill
        shade.layer?.backgroundColor = NSColor.black.cgColor
        big.layer?.cornerRadius = 34            // clipped (masksToBounds) so the picture itself has round corners
        big.layer?.masksToBounds = true
        big.layer?.contentsGravity = .resizeAspectFill
        bigShadow.layer?.cornerRadius = 34      // shadow lives on a separate view behind, since the cover itself must clip
        bigShadow.layer?.backgroundColor = NSColor.black.cgColor
        bigShadow.layer?.shadowColor = NSColor.black.cgColor
        bigShadow.layer?.shadowOpacity = 0.3
        bigShadow.layer?.shadowRadius = 18
        bigShadow.layer?.shadowOffset = CGSize(width: 0, height: -6)
        video.maxPixels = 1920   // full-screen backdrop: sharper than the small popover video
        video.isHidden = true
        for l in [dateL, timeL, compactL] { l.alignment = .center; l.textColor = .white; l.lineBreakMode = .byClipping; l.wantsLayer = true }
        applyTheme()
        [wash, shade, video, scrim, bigShadow, big, clockGlass, dateL, timeL, compactL, lyricsView, queueView, modePill, editor].forEach(addSubview)
        editor.isHidden = true
        editor.onChange = { [weak self] in self?.layoutContent(); self?.updateClock() }
        lyricsView.isHidden = true; queueView.isHidden = true
        lyricsView.onSeek = { [weak media] t in media?.seek(to: t) }
        queueView.onPlay = { [weak media] i in media?.playQueueItem(i) }
        modePill.wantsLayer = true
        modePill.addSubview(pillGlass)
        for (b, symbol, action) in [(lyricsB, "quote.bubble", #selector(lyricsTap)), (queueB, "list.bullet", #selector(queueTap))] {
            b.isBordered = false; b.imagePosition = .imageOnly; b.contentTintColor = .white
            b.target = self; b.action = action
            b.wantsLayer = true; b.layer?.cornerRadius = 23
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 20, weight: .semibold))
            modePill.addSubview(b)
        }
        layoutContent()

        Publishers.Merge3(media.$info.map { _ in () }, media.$artwork.map { _ in () }, media.$motionURL.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &bag)
        media.$artwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.prepareBlur() }
            .store(in: &bag)
        media.$motionURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.warmUp() }
            .store(in: &bag)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func warmUp() {
        guard locked, let url = media.motionURL, video.url != url else { return }
        video.load(url)   // buffers only; it plays when fullscreen opens
    }
    /// Builds the blurred colour wash off the main thread as soon as the artwork changes, so entering fullscreen doesn't stall.
    private func prepareBlur() {
        guard let art = media.artwork, blurCache?.art !== art else { return }
        let cg = art.cgImage(forProposedRect: nil, context: nil, hints: nil)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let b = cg.flatMap(Self.blurred)
            DispatchQueue.main.async { if self?.media.artwork === art { self?.blurCache = (art, b) } }
        }
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutContent() }

    /// Fonts bundled in Resources (copied into the app by build.sh) are registered once, before the first clock font is asked for.
    private static let clockFontsRegistered: Void = {
        for file in ["COOPBL.TTF", "Zapfino.ttf", "Blackmoor.ttf"] {
            if let url = Bundle.main.url(forResource: file, withExtension: nil) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }()

    /// The clock's typeface, picked in settings ("lockClockStyle"): serif (default), sans, rounded, mono or a named font.
    private func clockFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        _ = Self.clockFontsRegistered
        let size = size * CGFloat(UserDefaults.standard.object(forKey: "lockClockScale") as? Double ?? 1)   // size slider in settings
        let names = ["cooper": "Cooper Black", "zapfino": "Zapfino", "blackmoor": "BlackmoorLetPlain"]
        if let name = names[UserDefaults.standard.string(forKey: "lockClockStyle") ?? ""], let font = NSFont(name: name, size: size) { return font }
        let design: NSFontDescriptor.SystemDesign
        switch UserDefaults.standard.string(forKey: "lockClockStyle") {
        case "sans": design = .default
        case "rounded": design = .rounded
        case "mono": design = .monospaced
        default: design = .serif
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    func layoutContent() {
        let w = bounds.width, h = bounds.height
        // Liqoria layout: cover as wide as the card, its top ~29% down the screen, card ~72% down with a clear gap between.
        let side = LockCardView.size.width
        big.frame = NSRect(x: mode == .cover ? (w - side) / 2 : Self.listColumnX(w), y: h * 0.71 - side, width: side, height: side)
        bigShadow.frame = big.frame
        lyricsView.frame = NSRect(x: w * 0.46, y: h * 0.08, width: w * 0.46, height: h * 0.84)
        queueView.frame = lyricsView.frame
        layoutPill()
        // oversized so the blurred colours spread across the whole screen
        wash.frame = bounds.insetBy(dx: -w * 0.2, dy: -h * 0.2)
        [shade, video, scrim].forEach { $0.frame = bounds }
        dateL.font = clockFont(h * 0.032, .semibold)
        let weights: [String: NSFont.Weight] = ["ultralight": .ultraLight, "light": .light, "regular": .regular, "bold": .bold]
        timeL.font = clockFont(h * 0.15, weights[UserDefaults.standard.string(forKey: "lockClockWeight") ?? ""] ?? .light)
        dateL.frame = NSRect(x: 0, y: h * 0.84, width: w, height: h * 0.05)
        timeL.frame = NSRect(x: 0, y: h * 0.66, width: w, height: h * 0.19)
        compactL.frame = NSRect(x: 0, y: h * 0.902 - 14, width: w, height: 28)
        editor.frame = NSRect(x: w / 2 - 130, y: h * 0.46, width: 260, height: 150)
    }

    /// The corner buttons for lyrics and queue, each of which can be switched off in the settings.
    private func layoutPill() {
        let showL = showLyricsButton, showQ = showQueueButton
        lyricsB.isHidden = !showL; queueB.isHidden = !showQ
        modePill.isHidden = !showL && !showQ
        let visible = [(lyricsB, showL), (queueB, showQ)].filter { $0.1 }.map { $0.0 }
        let bw: CGFloat = 46, pad: CGFloat = 8, hgt: CGFloat = 54
        let pw = pad * 2 + bw * CGFloat(visible.count) + (visible.count > 1 ? 4 : 0)
        modePill.frame = NSRect(x: bounds.width - pw - 36, y: 36, width: pw, height: hgt)
        pillGlass.frame = modePill.bounds
        for (k, b) in visible.enumerated() { b.frame = NSRect(x: pad + CGFloat(k) * (bw + 4), y: (hgt - bw) / 2, width: bw, height: bw) }
        updatePillSelection(animated: false)
    }

    private func updatePillSelection(animated: Bool) {
        for (b, on) in [(lyricsB, mode == .lyrics), (queueB, mode == .queue)] {
            guard let l = b.layer else { continue }
            let to = (on ? NSColor.white.withAlphaComponent(0.24) : NSColor.clear).cgColor
            let from = l.presentation()?.backgroundColor ?? l.backgroundColor
            l.backgroundColor = to
            if animated { let a = CABasicAnimation(keyPath: "backgroundColor"); a.fromValue = from; a.toValue = to; a.duration = 0.3; a.timingFunction = .arrive; l.add(a, forKey: "sel") }
        }
    }

    @objc private func lyricsTap() { setMode(mode == .lyrics ? .cover : .lyrics) }
    @objc private func queueTap() { setMode(mode == .queue ? .cover : .queue) }

    /// Cover <-> lyrics <-> queue. The cover (when it is a plain image) and the card slide to the left column while the list fades
    /// and rises in on the right; the clock gets out of the way and the picture darkens a little so the text stays readable.
    func setMode(_ m: Mode) {
        guard m != mode else { return }
        let old = mode
        mode = m
        updateTheme(animated: true)
        let w = bounds.width, h = bounds.height, side = LockCardView.size.width
        let list = m != .cover
        let target = NSRect(x: list ? Self.listColumnX(w) : (w - side) / 2, y: h * 0.71 - side, width: side, height: side)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduce ? 0.2 : 0.65; ctx.timingFunction = .arrive
            self.big.animator().frame = target; self.bigShadow.animator().frame = target
            [self.dateL, self.timeL, self.compactL].forEach { $0.animator().alphaValue = list ? 0 : 1 }
            self.shade.animator().alphaValue = self.shadeLevel
        }
        let outgoing: NSView? = old == .lyrics ? lyricsView : old == .queue ? queueView : nil
        let incoming: NSView? = m == .lyrics ? lyricsView : m == .queue ? queueView : nil
        if let o = outgoing, o !== incoming {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.25; ctx.timingFunction = .leave; o.animator().alphaValue = 0 },
                                                 completionHandler: { [weak self] in if self?.mode == .cover || (o === self?.lyricsView ? self?.mode != .lyrics : self?.mode != .queue) { o.isHidden = true } })
        }
        if let i = incoming {
            i.isHidden = false
            i.layer?.removeAllAnimations()
            i.alphaValue = 1
            if !reduce {
                let g = CAAnimationGroup()
                let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 0; o.toValue = 1
                let t = CABasicAnimation(keyPath: "transform.translation.x"); t.fromValue = 40; t.toValue = 0
                g.animations = [o, t]; g.duration = 0.6; g.timingFunction = .arrive
                i.layer?.add(g, forKey: "in")
            }
            reloadContent()
        }
        lyricsTimer?.invalidate(); lyricsTimer = nil
        if m == .lyrics {
            let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickLyrics() }
            t.tolerance = 0.03
            lyricsTimer = t
        }
        updatePillSelection(animated: true)
        onModeChange?(m)
    }

    /// README images only: the corner buttons' glass gets the blurred picture behind it (see GlassBackground.setScreenshotBackdrop).
    func applyScreenshotGlass(_ full: CGImage) {
        guard !modePill.isHidden else { return }
        pillGlass.setScreenshotBackdrop(GlassBackground.glassCrop(full, rect: modePill.frame, scale: 2))
    }

    /// README images only: opens a list with sample content, without animation.
    func previewList(_ m: Mode, lyrics: [LyricLine], queue: [QueueItem]) {
        mode = m
        layoutContent()
        lyricsView.isHidden = m != .lyrics; queueView.isHidden = m != .queue
        [dateL, timeL, compactL].forEach { $0.alphaValue = 0 }
        shade.alphaValue = shadeLevel
        updatePillSelection(animated: false)
        if m == .lyrics { lyricsView.set(.synced(lyrics)); lyricsView.setPosition(lyrics.count > 2 ? lyrics[2].time : 0) } else { queueView.set(queue) }
    }

    /// Back to the plain cover without animation (entering and leaving fullscreen, unlock).
    func resetMode() {
        mode = .cover
        lyricsTimer?.invalidate(); lyricsTimer = nil
        lyricsView.isHidden = true; queueView.isHidden = true
        lyricsView.clear(); queueView.clear()
        hideEditor()
        contentKey = ""
        layoutContent()
    }

    private func tickLyrics() {
        guard mode == .lyrics, let i = media.info else { return }
        lyricsView.setPosition(i.position + (i.isPlaying ? Date().timeIntervalSince(media.sampleDate) : 0))
    }

    /// Loads what the open list shows for the song that is playing now.
    private func reloadContent() {
        guard let i = media.info else {
            (mode == .lyrics ? lyricsView.showMessage("Nothing is playing") : queueView.showMessage("Nothing is playing"))
            return
        }
        let key = i.key + (i.shuffle ? "|s" : "")
        contentKey = key
        refreshInk()   // the new song's colour, before its lines are built
        if mode == .lyrics {
            var answered = false
            lyricsStore.load(i) { [weak self] r in
                answered = true
                guard let self, self.mode == .lyrics, self.contentKey == key else { return }
                self.lyricsView.set(r)
            }
            if !answered { lyricsView.showMessage("Loading lyrics…") }
        } else if mode == .queue {
            if i.player == .spotify && !SpotifyAuth.shared.connected { queueView.showMessage("Connect Spotify in ORBT's settings to see its queue"); return }
            // Music plays a shuffled order it doesn't share with other apps; the playlist order would show the WRONG songs,
            // so what ORBT has seen play is shown instead (history, not the future)
            if i.player == .music && i.shuffle {
                queueView.setHeader("Recently played")
                queueView.playable = false
                let seen = media.recent
                if seen.isEmpty { queueView.showMessage("Apple Music doesn't share the shuffled queue. Songs you play will show up here.") } else { queueView.clear(); queueView.set(seen) }
                return
            }
            queueView.setHeader("Up Next")
            queueView.playable = i.player == .music
            queueView.clear()
            media.loadQueue { [weak self] items in
                guard let self, self.mode == .queue, self.contentKey == key else { return }
                self.queueView.set(items)
            }
        }
    }

    private var shadeLevel: CGFloat {
        let motion = media.motionURL != nil
        return mode == .cover ? (motion ? 0.15 : 0.22) : (motion ? 0.45 : 0.3)
    }

    /// Instant hide (on unlock and when leaving fullscreen).
    func setActive(_ on: Bool, keepVideo: Bool = false) {
        timer?.invalidate(); timer = nil
        guard !on else { return }
        resetMode()
        isHidden = true
        alphaValue = 1
        if keepVideo { video.pause() } else { video.stop() }   // keep it buffered while still locked
        video.isHidden = true
        lastPlaying = nil
    }

    private var fadingViews: [NSView] { [big, bigShadow, video, wash, shade, scrim, dateL, timeL, compactL, modePill] }

    /// README image only: a still frame of the moving artwork stands in for the video (an AVPlayer can't render offscreen).
    func previewMotionStill(_ img: NSImage) {
        isHidden = false
        alphaValue = 1
        wash.frame = bounds
        wash.layer?.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        shade.alphaValue = 0.15
        big.isHidden = true; bigShadow.isHidden = true; compactL.isHidden = true
        timeL.isHidden = false; dateL.isHidden = false
        updateClock()
    }

    /// Show the backdrop: the background fades in slowly (0.8s), the image (cover or video) faster (0.25s).
    func show() {
        fadeToken += 1
        timer?.invalidate()
        resetMode()
        let playing = media.info?.isPlaying == true
        lastPlaying = playing   // so refresh() doesn't animate the paused look itself; it is applied below
        fadingViews.forEach { $0.layer?.removeAllAnimations() }
        isHidden = false
        alphaValue = 1
        media.loadMotionIfNeeded()
        refresh()
        let imageAlpha: CGFloat = playing ? 1 : 0.62            // paused look: a little faded and smaller
        big.layer?.transform = big.scaled(playing ? 1 : 0.9)
        bigShadow.layer?.transform = bigShadow.scaled(playing ? 1 : 0.9)
        let shadeTarget = shade.alphaValue, scrimTarget = scrim.alphaValue
        fadingViews.forEach { $0.alphaValue = 0 }
        CATransaction.flush()   // finish the heavy first draw while invisible, so the fades below start on a ready screen
        [big, bigShadow].forEach { $0.fadeIn(to: imageAlpha, duration: 0.25) }
        let k: CGFloat = playing ? 1 : 0.9
        [big, bigShadow].forEach { $0.animateScale(to: k, from: k * 0.94) }   // the cover settles into place instead of just appearing
        video.fadeIn(to: imageAlpha, duration: 0.8)
        [wash, dateL, timeL, compactL, modePill].forEach { $0.fadeIn(to: 1, duration: 0.8) }
        shade.fadeIn(to: shadeTarget, duration: 0.8)
        scrim.fadeIn(to: scrimTarget, duration: 0.8)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateClock() }
    }

    /// Leaving fullscreen: the image fades out quickly, the background more slowly, then everything is hidden.
    func fadeOutAndHide() {
        fadeToken += 1
        let token = fadeToken
        timer?.invalidate(); timer = nil
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.fadeToken == token else { return }   // a newer show() cancels this hide
            self.setActive(false, keepVideo: true)
        }
        [big, bigShadow].forEach { $0.fadeOut(duration: 0.25) }
        [video, wash, shade, scrim, dateL, timeL, compactL, modePill, lyricsView, queueView].forEach { $0.fadeOut(duration: 0.5) }
        CATransaction.commit()
    }

    private func refresh() {
        guard !isHidden else { return }
        media.loadMotionIfNeeded()
        let motion = media.motionURL
        if let url = motion { video.isHidden = false; if video.url != url { video.load(url) }; video.resume() }
        else { video.stop(); video.isHidden = true }
        big.isHidden = motion != nil
        bigShadow.isHidden = motion != nil
        let playing = media.info?.isPlaying == true
        if lastPlaying != playing {
            let animated = lastPlaying != nil
            lastPlaying = playing
            // same pause look as the card: a little faded and a little smaller, springing back on play
            let scale: CGFloat = playing ? 1 : 0.9, alpha: CGFloat = playing ? 1 : 0.62
            if animated { big.animateScale(to: scale); bigShadow.animateScale(to: scale) }
            else { big.layer?.transform = big.scaled(scale); bigShadow.layer?.transform = bigShadow.scaled(scale) }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; $0.timingFunction = .arrive; self.big.animator().alphaValue = alpha; self.bigShadow.animator().alphaValue = alpha; self.video.animator().alphaValue = alpha }
        }
        timeL.isHidden = motion == nil
        dateL.isHidden = motion == nil
        compactL.isHidden = motion != nil
        shade.alphaValue = shadeLevel
        if mode != .cover, let i = media.info, contentKey != i.key + (i.shuffle ? "|s" : "") { reloadContent() }   // the song changed under an open list
        if media.artwork !== lastArt {
            lastArt = media.artwork
            let cg = media.artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            big.layer?.contents = cg
            wash.layer?.contents = (blurCache?.art === media.artwork ? blurCache?.image : nil) ?? cg.flatMap(Self.blurred)
            artLuma = cg.map(Self.luminance) ?? 0
        }
        updateTheme()
        updateClock()
    }

    /// Keeps the clock and buttons readable. Setting "lockContrast": auto, off, or high (always darken, white text).
    /// Auto: on a bright picture (a white album) the text takes the cover's own distinct colour, darkened (brown for a brown baby),
    /// or near-black when the cover has none. An open lyrics/queue list darkens the picture instead, because its text stays white.
    /// shortcut: with moving artwork the cover's brightness stands in for the video's, upgrade by sampling a video frame.
    private func updateTheme(animated: Bool = false) {
        let setting = UserDefaults.standard.string(forKey: "lockContrast") ?? "auto"
        let playing = media.info?.isPlaying == true
        // paused, the picture is faded and reads brighter, so switch a little earlier
        let bright = setting == "auto" && artLuma > (playing ? 0.55 : 0.45)
        let listOpen = mode != .cover
        darkUI = bright && !listOpen
        refreshInk()
        uiColor = darkUI ? SongTint.dark(for: media.artwork) : .white
        let level: CGFloat = listOpen ? (setting == "off" ? 0 : bright ? 0.5 : 0.3) : (setting == "high" ? 0.4 : 0)
        if animated { NSAnimationContext.runAnimationGroup { $0.duration = 0.65; $0.timingFunction = .arrive; self.scrim.animator().alphaValue = level } }
        else { scrim.alphaValue = level }
        applyTheme()
    }

    /// Lyrics text: white mixed with the song's colour when "Tint the lyrics" is on in the settings (off by default).
    private func refreshInk() {
        SongTint.ink = UserDefaults.standard.bool(forKey: "tintLyrics") ? SongTint.white(for: media.artwork) : .white
    }

    private func applyTheme() {
        let sh = NSShadow()
        sh.shadowColor = darkUI ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.35)
        sh.shadowBlurRadius = 10; sh.shadowOffset = .zero
        for l in [dateL, timeL, compactL] { l.textColor = uiColor; l.shadow = sh }
        lyricsB.contentTintColor = uiColor; queueB.contentTintColor = uiColor
        updateClock()   // the compact label carries its own colours
    }

    /// The most distinct colour of an image (ignoring near-white, near-black and grey), made vivid; nil for a grey cover.
    static func accentColor(_ cg: CGImage) -> NSColor? {
        let n = 32
        var px = [UInt8](repeating: 0, count: n * n * 4)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        var wsum = [CGFloat](repeating: 0, count: 12), rs = wsum, gs = wsum, bs = wsum   // 12 hue buckets of 30 degrees
        for i in 0..<(n * n) {
            let r = CGFloat(px[i * 4]) / 255, g = CGFloat(px[i * 4 + 1]) / 255, b = CGFloat(px[i * 4 + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            guard mx > 0.15, mx < 0.93, d / mx > 0.25 else { continue }
            var h: CGFloat = mx == r ? ((g - b) / d).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
            h *= 60; if h < 0 { h += 360 }
            let k = min(11, Int(h / 30)), s = d / mx
            rs[k] += r * s; gs[k] += g * s; bs[k] += b * s; wsum[k] += s
        }
        guard let k = wsum.indices.max(by: { wsum[$0] < wsum[$1] }), wsum[k] > CGFloat(n * n) * 0.04 else { return nil }
        let c = NSColor(srgbRed: rs[k] / wsum[k], green: gs[k] / wsum[k], blue: bs[k] / wsum[k], alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return NSColor(hue: h, saturation: min(max(s, 0.5), 0.9), brightness: 1, alpha: 1)
    }

    /// Average brightness (0 black ... 1 white) of an image, from a 16x16 thumbnail.
    private static func luminance(_ cg: CGImage) -> CGFloat {
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        var sum: CGFloat = 0
        for i in 0..<(n * n) { sum += 0.2126 * CGFloat(px[i * 4]) + 0.7152 * CGFloat(px[i * 4 + 1]) + 0.0722 * CGFloat(px[i * 4 + 2]) }
        return sum / CGFloat(n * n) / 255
    }

    private static func blurred(_ cg: CGImage) -> CGImage? {
        let img = CIImage(cgImage: cg)
        guard let blur = CIFilter(name: "CIGaussianBlur"), let color = CIFilter(name: "CIColorControls") else { return nil }
        blur.setValue(img.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(70, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage?.cropped(to: img.extent) else { return nil }
        color.setValue(blurred, forKey: kCIInputImageKey)
        color.setValue(1.8, forKey: kCIInputSaturationKey)   // vivid blobs like Liqoria's
        color.setValue(0.02, forKey: kCIInputBrightnessKey)
        guard let out = color.outputImage else { return nil }
        return ci.createCGImage(out, from: img.extent)
    }

    private func updateClock() {
        let now = Date()
        let tf = DateFormatter(); tf.timeStyle = .short; tf.dateStyle = .none
        let df = DateFormatter(); df.dateFormat = "EEE d MMM"
        let time = tf.string(from: now), date = df.string(from: now)
        // With Liquid Glass the glass below is cut to the digits' shape; only a faint white stays on top so the shape still reads
        let glassOn = UserDefaults.standard.object(forKey: "lockClockGlass") as? Bool ?? false
        let ink = glassOn ? NSColor.white.withAlphaComponent(0.15) : uiColor
        timeL.stringValue = time
        dateL.stringValue = date
        timeL.textColor = ink; dateL.textColor = ink
        let centered = NSMutableParagraphStyle(); centered.alignment = .center
        let s = NSMutableAttributedString(string: time, attributes: [.font: clockFont(20, .bold), .foregroundColor: ink, .paragraphStyle: centered])
        s.append(NSAttributedString(string: "  " + date, attributes: [.font: clockFont(20, .regular), .foregroundColor: ink.withAlphaComponent(0.85), .paragraphStyle: centered]))
        compactL.attributedStringValue = s

        let rect = clockRect()
        clockGlass.frame = rect
        clockGlass.isHidden = !glassOn
        clockGlass.setTint(NSColor.white.withAlphaComponent(0.5 * CGFloat(UserDefaults.standard.object(forKey: "lockClockGlassy") as? Double ?? 0.3)))   // 0 = fully clear
        guard glassOn else { clockGlass.layer?.mask = nil; return }
        // the glass shows only where the digits are: each visible clock line is drawn white into a mask
        let cut = CALayer()
        cut.frame = CGRect(origin: .zero, size: rect.size)
        for label in media.motionURL != nil ? [timeL, dateL] : [compactL] {
            let text = NSMutableAttributedString(attributedString: label.attributedStringValue)
            text.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: text.length))
            let box = text.size()
            let line = CATextLayer()
            line.string = text
            line.alignmentMode = .center
            line.contentsScale = 2
            line.frame = CGRect(x: label.frame.minX - rect.minX, y: label.frame.midY - rect.minY - box.height / 2, width: label.frame.width, height: box.height)
            cut.addSublayer(line)
        }
        clockGlass.layer?.mask = cut
    }

    /// Where the clock's text sits: the time and date while a video plays, otherwise the small line at the top.
    private func clockRect() -> NSRect {
        let w = bounds.width, h = bounds.height
        if media.motionURL != nil { return NSRect(x: w * 0.3, y: h * 0.655, width: w * 0.4, height: h * 0.245) }
        return NSRect(x: w * 0.3, y: h * 0.902 - 18, width: w * 0.4, height: 36)
    }

    /// A long press on the clock opens the editor. A quick tap, or a click anywhere else, closes fullscreen as before.
    override func mouseDown(with event: NSEvent) {
        if editorOpen { hideEditor(); return }   // a click outside the editor closes it first
        if clockRect().contains(convert(event.locationInWindow, from: nil)) {
            pressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.pressTimer = nil
                self?.showEditor()
            }
            return
        }
        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
        guard let timer = pressTimer else { return }   // the long press already opened the editor
        timer.invalidate(); pressTimer = nil
        onClick?()
    }

    private func showEditor() {
        editor.load()
        editor.isHidden = false
        editor.fadeIn(to: 1, duration: 0.25)
        editorOpen = true
    }

    private func hideEditor() {
        editor.isHidden = true
        editorOpen = false
    }
}

/// Slider that takes its first click even in a panel that never becomes active (the lock screen one never does).
private final class FirstMouseSlider: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Opened by a long press on the clock: a size slider and a Liquid Glass checkbox. It writes the same settings as the Settings window.
final class ClockEditorView: NSView {
    var onChange: (() -> Void)?
    private let glass = GlassBackground(frame: .zero, radius: 22, tint: NSColor.black.withAlphaComponent(0.2), blur: 4)
    private let size = FirstMouseSlider(value: 1, minValue: 0.6, maxValue: 1.4, target: nil, action: nil)
    private let glassBox = PressButton()
    private let amount = FirstMouseSlider(value: 0.3, minValue: 0, maxValue: 1, target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.autoresizingMask = [.width, .height]
        func caption(_ text: String, y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 12, weight: .semibold); l.textColor = .white
            l.frame = NSRect(x: 16, y: y, width: 228, height: 16)
            return l
        }
        size.frame = NSRect(x: 16, y: 98, width: 228, height: 20)
        size.target = self; size.action = #selector(sizeChanged)
        glassBox.frame = NSRect(x: 16, y: 66, width: 228, height: 22)
        amount.frame = NSRect(x: 16, y: 18, width: 228, height: 20)
        amount.target = self; amount.action = #selector(amountChanged)
        glassBox.setButtonType(.switch)
        glassBox.attributedTitle = NSAttributedString(string: "Liquid Glass", attributes: [.foregroundColor: NSColor.white])
        glassBox.target = self; glassBox.action = #selector(glassChanged)
        [glass, caption("Clock size", y: 124), size, glassBox, caption("Glass amount (left = clear)", y: 44), amount].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the saved values before the editor appears.
    func load() {
        let d = UserDefaults.standard
        size.doubleValue = d.object(forKey: "lockClockScale") as? Double ?? 1
        glassBox.state = (d.object(forKey: "lockClockGlass") as? Bool ?? false) ? .on : .off
        amount.doubleValue = d.object(forKey: "lockClockGlassy") as? Double ?? 0.3
    }
    @objc private func amountChanged() { UserDefaults.standard.set(amount.doubleValue, forKey: "lockClockGlassy"); onChange?() }

    @objc private func sizeChanged() { UserDefaults.standard.set(size.doubleValue, forKey: "lockClockScale"); onChange?() }
    @objc private func glassChanged() { UserDefaults.standard.set(glassBox.state == .on, forKey: "lockClockGlass"); onChange?() }
}

/// Puts a window into its own top-level space at SkyLight's "lock screen" level, so it stays visible over the lock screen.
/// shortcut: private SkyLight calls (same ones Liqoria imports; found by testing), so a macOS update may break them; returns a status string.
enum SkyLightSpace {
    private typealias MainConn = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> Int
    private typealias SetLevel = @convention(c) (Int32, Int, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias WinSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
    private typealias CurSpace = @convention(c) (Int32, CFString) -> Int

    private static func sym<T>(_ h: UnsafeMutableRawPointer, _ name: String, _ t: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: t) } }

    static func attach(_ w: NSWindow, levelOffset: Int32 = 0) -> String {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mainConn = sym(h, "SLSMainConnectionID", MainConn.self),
              let spaceCreate = sym(h, "SLSSpaceCreate", SpaceCreate.self),
              let setLevel = sym(h, "SLSSpaceSetAbsoluteLevel", SetLevel.self),
              let showSpaces = sym(h, "SLSShowSpaces", ShowSpaces.self),
              let addWin = sym(h, "SLSAddWindowsToSpaces", WinSpaces.self),
              let removeWin = sym(h, "SLSRemoveWindowsFromSpaces", WinSpaces.self),
              let curSpace = sym(h, "SLSManagedDisplayGetCurrentSpace", CurSpace.self),
              let levelPtr = dlsym(h, "kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock")
        else { return "SkyLight symbols missing" }
        let cid = mainConn()
        let space = spaceCreate(cid, 1, nil)
        _ = setLevel(cid, space, levelPtr.assumingMemoryBound(to: Int32.self).pointee + levelOffset)
        _ = showSpaces(cid, [space] as CFArray)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue(), let s = CFUUIDCreateString(nil, uuid) {
            let cur = curSpace(cid, s)
            _ = removeWin(cid, [w.windowNumber] as CFArray, [cur] as CFArray)
        }
        return "space \(space), add \(addWin(cid, [w.windowNumber] as CFArray, [space] as CFArray))"
    }
}

/// Shows the card (and, on a click on the cover, a full-screen backdrop) over the macOS lock screen while the Mac is locked.
/// The windows are created at launch and revealed on lock; each sits in its own SkyLight space, the backdrop one level below the card.
/// shortcut: relies on undocumented lock screen behaviour and the screenIsLocked notices, so a future macOS may stop it.
final class LockScreenController {
    private let media: MediaController
    private let card: LockCardView
    private let backdrop: LockBackdropView
    private let cardPanel: NSPanel
    private let backdropPanel: NSPanel
    private var tokens: [NSObjectProtocol] = []
    private var fullscreen = false

    init(media: MediaController) {
        self.media = media
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        backdrop = LockBackdropView(media: media, frame: NSRect(origin: .zero, size: screen.size))
        card = LockCardView(media: media)
        backdropPanel = LockScreenController.makePanel(frame: screen, shadow: false)
        cardPanel = LockScreenController.makePanel(frame: NSRect(origin: .zero, size: LockCardView.size), shadow: true)
        backdropPanel.contentView = backdrop
        cardPanel.contentView = card
        // Put each window in its own SkyLight space at the lock screen level (the backdrop one level below the card).
        // These calls are what make the card visible on the lock screen: do not remove them with any logging.
        backdropPanel.orderFrontRegardless()
        _ = SkyLightSpace.attach(backdropPanel, levelOffset: -1)
        cardPanel.orderFrontRegardless()
        _ = SkyLightSpace.attach(cardPanel)
        place()

        card.onCoverTap = { [weak self] in self?.setFullscreen(!(self?.fullscreen ?? false)) }
        backdrop.onClick = { [weak self] in self?.setFullscreen(false) }
        backdrop.onModeChange = { [weak self] m in self?.moveCard(toList: m != .cover, animated: true) }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.place() })
        let dnc = DistributedNotificationCenter.default()
        tokens.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.show() })
        tokens.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.hide() })
    }

    private static func makePanel(frame: NSRect, shadow: Bool) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = shadow
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }

    /// Card centred horizontally and low on the screen, just above the unlock prompt; moved only when the screen setup changes.
    private func place() {
        let f = NSScreen.main?.frame ?? .zero
        cardPanel.setFrameOrigin(NSPoint(x: f.midX - LockCardView.size.width / 2, y: f.minY + f.height * 0.22 - LockCardView.size.height / 2))
        backdropPanel.setFrame(f, display: false)
        backdrop.setFrameSize(f.size)
    }

    deinit { tokens.forEach { DistributedNotificationCenter.default().removeObserver($0) } }

    /// The card sits under the cover: centred normally, in the left column while lyrics or the queue are open.
    private func moveCard(toList: Bool, animated: Bool) {
        let f = NSScreen.main?.frame ?? .zero
        let x = toList ? f.minX + LockBackdropView.listColumnX(f.width) : f.midX - LockCardView.size.width / 2
        let target = NSRect(origin: NSPoint(x: x, y: cardPanel.frame.origin.y), size: cardPanel.frame.size)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { cardPanel.setFrame(target, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.65; ctx.timingFunction = .arrive
            self.cardPanel.animator().setFrame(target, display: true)
        }
    }

    private func setFullscreen(_ on: Bool) {
        guard on != fullscreen else { return }
        fullscreen = on
        if on {
            backdropPanel.ignoresMouseEvents = false
            backdropPanel.orderFrontRegardless(); cardPanel.orderFrontRegardless()
            backdrop.show()
        } else {
            backdropPanel.ignoresMouseEvents = true
            backdrop.fadeOutAndHide()
            moveCard(toList: false, animated: true)
        }
        card.setFullscreen(on)
    }

    private func show() {
        let enabled = UserDefaults.standard.object(forKey: "lockScreenPlayer") as? Bool ?? true
        guard enabled else { return }
        media.refresh()
        fullscreen = false
        backdrop.locked = true
        card.setActive(true)
        cardPanel.ignoresMouseEvents = false
        cardPanel.orderFrontRegardless()
    }

    private func hide() {
        fullscreen = false
        backdrop.locked = false
        backdrop.setActive(false)               // instant, no animation, on unlock
        moveCard(toList: false, animated: false)
        backdropPanel.ignoresMouseEvents = true
        card.setActive(false)   // hides the card and stops its timers
        cardPanel.ignoresMouseEvents = true
    }
}
