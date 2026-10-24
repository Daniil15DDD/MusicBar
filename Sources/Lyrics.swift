import AppKit

struct LyricLine { let time: Double; let text: String }

enum LyricsResult { case synced([LyricLine]), plain([String]), instrumental, none }

/// Lyrics from LRCLIB (https://lrclib.net, a free open lyrics database): time-synced lines when it has them, otherwise plain text.
/// Only the song title, artist, album and length are sent. Results are cached for the session; a network failure is not cached.
final class LyricsStore {
    private var cache: [String: LyricsResult] = [:]   // main thread only

    func load(_ i: NowPlaying, done: @escaping (LyricsResult) -> Void) {
        let key = i.key
        if let c = cache[key] { done(c); return }
        Task {
            let r = await Self.fetch(i)
            await MainActor.run {
                if let r { self.cache[key] = r }
                done(r ?? .none)
            }
        }
    }

    private static func request(_ path: String, _ items: [URLQueryItem]) async -> (Data?, Int?) {
        guard var c = URLComponents(string: "https://lrclib.net/api/" + path) else { return (nil, nil) }
        c.queryItems = items
        guard let url = c.url else { return (nil, nil) }
        var r = URLRequest(url: url)
        r.timeoutInterval = 10
        r.setValue("ORBT (https://github.com/Daniil15DDD/ORBT)", forHTTPHeaderField: "User-Agent")
        guard let (d, resp) = try? await URLSession.shared.data(for: r), let code = (resp as? HTTPURLResponse)?.statusCode else { return (nil, nil) }
        return (d, code)
    }

    private static func parse(_ o: [String: Any]) -> LyricsResult? {
        if o["instrumental"] as? Bool == true { return .instrumental }
        if let s = o["syncedLyrics"] as? String, case let l = parseLRC(s), !l.isEmpty { return .synced(l) }
        if let p = o["plainLyrics"] as? String {
            let l = p.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !l.isEmpty { return .plain(l) }
        }
        return nil
    }

    /// nil = the network failed (nothing is cached), `.none` = LRCLIB has no lyrics for this song.
    private static func fetch(_ i: NowPlaying) async -> LyricsResult? {
        var exact: [URLQueryItem] = [.init(name: "track_name", value: i.title), .init(name: "artist_name", value: i.artist)]
        if !i.album.isEmpty { exact.append(.init(name: "album_name", value: i.album)) }
        if i.duration > 0 { exact.append(.init(name: "duration", value: String(Int(i.duration.rounded())))) }
        let (d1, s1) = await request("get", exact)
        if s1 == 200, let d = d1, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let r = parse(o) { return r }
        // no exact match (different album or length): take the best result of a search
        let (d2, s2) = await request("search", [.init(name: "track_name", value: i.title), .init(name: "artist_name", value: i.artist)])
        if s2 == 200, let d = d2, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
            let parsed = arr.compactMap(parse)
            if let s = parsed.first(where: { if case .synced = $0 { return true } else { return false } }) { return s }
            if let first = parsed.first { return first }
        }
        return s1 == nil && s2 == nil ? nil : LyricsResult.none
    }

    /// "[01:23.45] text" lines (a line can carry several stamps); empty lines are dropped.
    static func parseLRC(_ s: String) -> [LyricLine] {
        guard let re = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#) else { return [] }
        var out: [LyricLine] = []
        for raw in s.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let ms = re.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = ms.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for m in ms {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0, ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                out.append(LyricLine(time: mm * 60 + ss, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// A gaussian blur for a layer's own content (the private CAFilter Core Animation uses itself); nil if it is missing.
private func makeBlur() -> NSObject? {
    guard let cls = NSClassFromString("CAFilter") as? NSObject.Type,
          let f = cls.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return nil }
    f.setValue("blur", forKey: "name")
    f.setValue(0.0, forKey: "inputRadius")
    return f
}

/// `tinted`: lyrics only, takes the song's colour when that setting is on (everything else stays white).
private func makeLabel(_ size: CGFloat, _ weight: NSFont.Weight, alpha: CGFloat = 1, wrapping: String? = nil, tinted: Bool = false) -> NSTextField {
    let l = wrapping.map { NSTextField(wrappingLabelWithString: $0) } ?? NSTextField(labelWithString: "")
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = (tinted ? SongTint.ink : NSColor.white).withAlphaComponent(alpha)
    l.isSelectable = false
    l.drawsBackground = false
    l.wantsLayer = true
    return l
}

/// Apple-Music-style lyrics: the current line is big and bright, the others fade and blur away from it, and the list
/// scrolls with a critically damped spring. Tap a line to jump there. Plain (unsynced) lyrics scroll with the trackpad.
final class LyricsView: NSView {
    var onSeek: ((Double) -> Void)?
    private let host = FlippedView()
    private var labels: [NSTextField] = []
    private var blurFilters: [NSObject?] = []
    private var blurValue: [CGFloat] = []
    private var lines: [LyricLine] = []
    private var plain = false
    private var rowTop: [CGFloat] = [], rowH: [CGFloat] = []
    private var hostH: CGFloat = 0
    private var active = -1
    private let message = makeLabel(30, .semibold, alpha: 0.7, tinted: true)
    private let gap: CGFloat = 28
    private var fontSize: CGFloat { max(30, bounds.height * 0.05) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        host.wantsLayer = true
        addSubview(host)
        message.alignment = .center
        message.alphaValue = 0
        addSubview(message)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func showMessage(_ s: String) {
        clear()
        message.stringValue = s
        message.frame = NSRect(x: 0, y: bounds.height * 0.55 - 20, width: bounds.width, height: 40)
        message.fadeIn(to: 1, duration: 0.5)
    }

    func clear() {
        labels.forEach { $0.removeFromSuperview() }
        labels = []; blurFilters = []; blurValue = []; lines = []; rowTop = []; rowH = []
        active = -1; hostH = 0
        message.layer?.removeAllAnimations()
        message.alphaValue = 0
    }

    func set(_ r: LyricsResult) {
        switch r {
        case .none: showMessage("No lyrics for this song")
        case .instrumental: showMessage("Instrumental")
        case .synced(let l): build(l.map { $0.text }, lines: l, plain: false)
        case .plain(let l): build(l, lines: [], plain: true)
        }
    }

    private func build(_ texts: [String], lines newLines: [LyricLine], plain isPlain: Bool) {
        clear()
        lines = newLines; plain = isPlain
        let w = bounds.width - 20
        var y: CGFloat = 0
        for t in texts {
            let l = makeLabel(fontSize, .bold, wrapping: t, tinted: true)
            l.lineBreakMode = .byWordWrapping
            l.maximumNumberOfLines = 0
            let h = ceil(l.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 10_000)).height ?? fontSize * 1.3) + 4
            l.frame = NSRect(x: 0, y: y, width: w, height: h)
            host.addSubview(l)
            labels.append(l); blurFilters.append(nil); blurValue.append(0)
            rowTop.append(y); rowH.append(h)
            y += h + gap
        }
        hostH = max(y - gap, 0)
        host.frame = NSRect(x: 10, y: 0, width: bounds.width - 10, height: hostH)
        for i in labels.indices { apply(i, animated: false) }
        if plain { moveHost(toY: bounds.height - hostH, animated: false) } else { scroll(to: 0, animated: false) }
        host.fadeIn(to: 1, duration: 0.6)
    }

    /// Called about ten times a second with the playback position; only moves when the current line changes.
    func setPosition(_ t: Double) {
        guard !plain, !lines.isEmpty else { return }
        var idx = -1
        for (i, l) in lines.enumerated() { if l.time <= t + 0.15 { idx = i } else { break } }
        guard idx != active else { return }
        let first = active == -1
        active = idx
        for i in labels.indices { apply(i, animated: !first) }
        scroll(to: max(idx, 0), animated: !first)
    }

    // MARK: Look of each line

    private func leftScaled(_ v: NSView, _ s: CGFloat) -> CATransform3D {
        guard let l = v.layer else { return CATransform3DIdentity }
        let a = l.anchorPoint, b = l.bounds
        let r = CGPoint(x: -b.width * a.x, y: b.height * (0.5 - a.y))   // pivot (left edge, middle) relative to the anchor
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(r.x, r.y, 0), s, s, 1), -r.x, -r.y, 0)
    }

    private func apply(_ i: Int, animated: Bool) {
        guard let l = labels[i].layer else { return }
        let d = plain ? 0 : (active < 0 ? 1 : abs(i - active))
        let alpha: Float = plain ? 0.92 : (d == 0 ? 1 : (d > 7 ? 0 : max(0.16, 0.58 - 0.1 * Float(d - 1))))
        let blur: CGFloat = d == 0 ? 0 : min(7, 1.6 + 1.5 * CGFloat(d - 1))
        let scale: CGFloat = d == 0 ? 1 : 0.92
        let go = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let fromO = l.presentation()?.opacity ?? l.opacity
        l.opacity = alpha
        if go { let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = fromO; a.toValue = alpha; a.duration = 0.5; a.timingFunction = .arrive; l.add(a, forKey: "o") }

        let fromT = l.presentation()?.transform ?? l.transform
        let toT = leftScaled(labels[i], scale)
        l.transform = toT
        if go {
            let a = CASpringAnimation(keyPath: "transform")
            a.fromValue = NSValue(caTransform3D: fromT); a.toValue = NSValue(caTransform3D: toT)
            a.mass = 1; a.stiffness = 200; a.damping = 28
            a.duration = a.settlingDuration
            l.add(a, forKey: "t")
        }

        if blur > 0 && d <= 7 {
            if blurFilters[i] == nil { blurFilters[i] = makeBlur() }
            if let f = blurFilters[i] {
                let from = blurValue[i]
                f.setValue(blur, forKey: "inputRadius")
                l.filters = [f]
                if go && from != blur { let a = CABasicAnimation(keyPath: "filters.blur.inputRadius"); a.fromValue = from; a.toValue = blur; a.duration = 0.5; a.timingFunction = .arrive; l.add(a, forKey: "b") }
                blurValue[i] = blur
            }
        } else {
            l.filters = nil; blurValue[i] = 0
        }
    }

    // MARK: Scrolling

    private func scroll(to idx: Int, animated: Bool) {
        guard idx < rowTop.count else { return }
        // the host is flipped: its origin is its bottom edge in our coordinates, and rows are measured from its top
        let target = bounds.height * 0.58                       // the current line sits 42% from the top
        moveHost(toY: target - hostH + rowTop[idx] + rowH[idx] / 2, animated: animated)
    }

    private func moveHost(toY y: CGFloat, animated: Bool) {
        guard let l = host.layer else { return }
        let from = l.presentation()?.position.y ?? l.position.y
        host.frame.origin.y = y
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let a = CASpringAnimation(keyPath: "position.y")
        a.fromValue = from; a.toValue = l.position.y
        a.mass = 1; a.stiffness = 170; a.damping = 26   // response ~0.48s, damping ratio ~1: no bounce
        a.duration = a.settlingDuration
        l.add(a, forKey: "scroll")
    }

    override func scrollWheel(with e: NSEvent) {
        guard plain, hostH > bounds.height else { return }
        let y = min(max(host.frame.origin.y - e.scrollingDeltaY, bounds.height - hostH), 0)
        host.layer?.removeAnimation(forKey: "scroll")
        host.frame.origin.y = y
    }

    override func mouseDown(with e: NSEvent) {
        guard !plain else { return }
        let p = host.convert(e.locationInWindow, from: nil)
        if let i = rowTop.indices.first(where: { p.y >= rowTop[$0] - gap / 2 && p.y <= rowTop[$0] + rowH[$0] + gap / 2 }), i < lines.count {
            onSeek?(lines[i].time)
        }
    }
}

/// "Up Next": the following tracks of the current Apple Music playlist or album; tap one to play it.
final class QueueView: NSView {
    var onPlay: ((Int) -> Void)?
    /// Apple Music rows play the song when tapped; Spotify's Web API can't jump to a queue position, so those rows are read-only.
    var playable = true
    private let header = makeLabel(34, .bold)
    private let message = makeLabel(26, .medium, alpha: 0.7, wrapping: "")
    private var rows: [QueueRow] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        header.stringValue = "Up Next"
        addSubview(header); addSubview(message)
        message.alignment = .center
        message.alphaValue = 0
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}   // clicks on the empty part of the column do nothing

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 12, y: bounds.height - 50, width: bounds.width - 24, height: 42)
    }

    func setHeader(_ s: String) { header.stringValue = s }

    func clear() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        message.layer?.removeAllAnimations(); message.alphaValue = 0
    }

    /// A short explanation in the middle of the column; long text wraps into centred lines instead of being cut off.
    func showMessage(_ s: String) {
        clear()
        message.stringValue = s
        message.alignment = .center
        message.lineBreakMode = .byWordWrapping
        message.maximumNumberOfLines = 0
        let w = min(bounds.width - 60, 520)
        let h = ceil(message.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 10_000)).height ?? 40) + 4
        message.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height * 0.5 - h / 2, width: w, height: h)
        message.fadeIn(to: 1, duration: 0.5)
    }

    func set(_ items: [QueueItem]) {
        clear()
        guard !items.isEmpty else { showMessage("Nothing is queued after this song"); return }
        let rowH: CGFloat = 80
        let n = min(items.count, max(1, Int((bounds.height - 84) / rowH)))
        let t0 = CACurrentMediaTime()
        for (k, item) in items.prefix(n).enumerated() {
            let r = QueueRow(item: item, frame: NSRect(x: 0, y: bounds.height - 70 - CGFloat(k + 1) * rowH, width: bounds.width, height: rowH - 6), hoverable: playable)
            if playable { r.onClick = { [weak self, weak r] in r?.pulse(0.97); self?.onPlay?(item.index) } }
            addSubview(r); rows.append(r)
            // each row rises into place a beat after the one above it
            guard let l = r.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { continue }
            let g = CAAnimationGroup()
            let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 0; o.toValue = 1
            let m = CABasicAnimation(keyPath: "transform.translation.y"); m.fromValue = -18; m.toValue = 0
            g.animations = [o, m]; g.duration = 0.55; g.timingFunction = .arrive
            g.beginTime = t0 + 0.045 * Double(k); g.fillMode = .backwards
            l.add(g, forKey: "in")
        }
    }
}

private final class QueueRow: ClickView {
    private let hover = CALayer()

    init(item: QueueItem, frame: NSRect, hoverable: Bool) {
        super.init(frame: frame)
        wantsLayer = true
        hover.cornerRadius = 20; hover.backgroundColor = NSColor.white.cgColor; hover.opacity = 0
        layer?.addSublayer(hover)
        let num = makeLabel(20, .semibold, alpha: 0.5); num.stringValue = "\(item.number)"; num.alignment = .center
        num.frame = NSRect(x: 8, y: (frame.height - 26) / 2, width: 44, height: 26)
        let title = makeLabel(25, .semibold); title.stringValue = item.title; title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 64, y: frame.height / 2 - 1, width: frame.width - 64 - 90, height: 30)
        let artist = makeLabel(19, .medium, alpha: 0.65); artist.stringValue = item.artist; artist.lineBreakMode = .byTruncatingTail
        artist.frame = NSRect(x: 64, y: frame.height / 2 - 28, width: frame.width - 64 - 90, height: 24)
        let dur = makeLabel(19, .medium, alpha: 0.5); dur.stringValue = String(format: "%d:%02d", Int(item.duration) / 60, Int(item.duration) % 60); dur.alignment = .right
        dur.frame = NSRect(x: frame.width - 90, y: (frame.height - 24) / 2, width: 78, height: 24)
        [num, title, artist, dur].forEach(addSubview)
        if hoverable { addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); hover.frame = bounds; CATransaction.commit() }
    override func mouseEntered(with event: NSEvent) { setHover(0.12) }
    override func mouseExited(with event: NSEvent) { setHover(0) }
    private func setHover(_ o: Float) {
        let from = hover.presentation()?.opacity ?? hover.opacity
        hover.opacity = o
        let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = from; a.toValue = o; a.duration = 0.2; a.timingFunction = .arrive
        hover.add(a, forKey: "h")
    }
}
