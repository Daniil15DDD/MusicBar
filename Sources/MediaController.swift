import AppKit
import Combine

enum Player: String, CaseIterable {
    case music, spotify
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    var appName: String { self == .music ? "Music" : "Spotify" }
    var displayName: String { self == .music ? "Apple Music" : "Spotify" }
}

struct NowPlaying: Equatable {
    var player: Player
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var shuffle = false
    var repeatMode = "off"      // off / all / one
    var favorited = false
    var bpm: Double = 0         // Apple Music tag, 0 when unknown
    var uri = ""                // Spotify: "spotify:track:..." (needed for the Web API), empty otherwise
    /// Stable per-track number used to seed the pulse pattern.
    var seed: Int { key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } }
    var key: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

struct QueueItem {
    let index: Int      // position in the current playlist, used to play it
    let number: Int     // 1, 2, 3 ... shown in the list
    let title: String
    let artist: String
    let duration: Double
    var album: String = ""
}

/// Reads Music/Spotify through AppleScript (public, no private APIs).
/// Updates are event-driven (distributed notifications) plus a slow safety poll.
final class MediaController: ObservableObject {
    @Published private(set) var info: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lastArtwork: NSImage?
    /// Small pre-scaled copy of the cover for the menu bar, so SwiftUI never re-scales the full-size image on every redraw.
    @Published private(set) var thumbnail: NSImage?
    @Published private(set) var permissionDenied = false
    /// Name of a running player macOS refused us access to (Automation permission), so the UI can say what to do.
    @Published private(set) var deniedPlayer: String?
    /// Apple's moving artwork for the current album, when it has one (nil = show the static cover).
    @Published private(set) var motionURL: URL?
    private var recentlyPlayed: [QueueItem] = []        // main thread: songs ORBT has seen finish or change, newest first
    private var spotifySaved: [String: Bool] = [:]      // main thread: song address -> in the user's Spotify library
    private var spotifyChecking = Set<String>()
    private var motionKey = ""
    private var motionCache: [String: URL?] = [:]   // main-thread only; a nil value means "checked, none"
    /// Wall-clock moment `info.position` was sampled, used to interpolate the progress bar.
    private(set) var sampleDate = Date()

    private let queue = DispatchQueue(label: "musicbar.media")
    private let cmdQueue = DispatchQueue(label: "musicbar.cmd", qos: .userInitiated)   // slow commands must not block refreshes
    /// Favourite we set on click; held until Music confirms it so a stale read can't flip the heart back.
    private var pendingFav: (key: String, value: Bool, until: Date)?
    private var artCache: [String: NSImage] = [:]   // queue-confined
    private var artKey = ""                          // queue-confined
    private var artTries: [String: Int] = [:]        // queue-confined: cover lookups per song (it can be missing at first)
    /// Play state we set on click; stale refreshes are ignored until it expires so the UI never flips back.
    private var pendingPlay: (value: Bool, until: Date, click: Bool)?
    private var timer: Timer?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// Static instance for rendering README images (`--render`); no observers or timers.
    private var isDemo = false   // README renders: no network lookups, so the image shows exactly what it is told to

    init(demo: NowPlaying, artwork: NSImage) {
        info = demo
        self.artwork = artwork
        lastArtwork = artwork
        isDemo = true
    }

    init() {
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            tokens.append((dnc, dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] n in
                // The notification already carries the play state: show it now, fetch full details after.
                if let st = n.userInfo?["Player State"] as? String { self?.applyPlayState(st == "Playing") }
                self?.refresh()
            }))
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append((ws, ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 1
        refresh()
    }

    deinit {
        timer?.invalidate()
        tokens.forEach { $0.0.removeObserver($0.1) }
    }

    // MARK: Reading

    func refresh() {
        let preferred = UserDefaults.standard.string(forKey: "preferredPlayer") ?? "auto"
        queue.async { [weak self] in
            guard let self else { return }
            var denied = false
            var deniedName: String?
            var candidates: [NowPlaying] = []
            for p in Player.allCases where preferred == "auto" || preferred == p.rawValue {
                guard !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty else { continue }
                let (np, err) = self.fetch(p)
                if err == -1743 { denied = true; deniedName = p.displayName }
                if let np { candidates.append(np) }
            }
            let chosen = candidates.first(where: { $0.isPlaying }) ?? candidates.first
            var art: NSImage?
            if let c = chosen {
                if c.key != self.artKey {
                    self.artKey = c.key
                    if self.artCache.count > 20 { self.artCache = self.artCache.filter { $0.key == c.key }; self.artTries = [:] }
                }
                // The cover can be missing right at the start of a song; retry on the next few refreshes, then use the catalogue.
                if self.artCache[c.key] == nil, (self.artTries[c.key] ?? 0) < 4 {
                    self.artTries[c.key, default: 0] += 1
                    if let img = self.fetchArtwork(c) { self.artCache[c.key] = img }
                }
                art = self.artCache[c.key]
            }
            DispatchQueue.main.async {
                var chosen = chosen
                // Spotify's scripting has no "saved" flag: it comes from the Web API (when connected) and is remembered per song
                if chosen?.player == .spotify, SpotifyAuth.shared.connected, let u = chosen?.uri, !u.isEmpty {
                    chosen?.favorited = self.spotifySaved[u] ?? false
                    if self.spotifySaved[u] == nil { self.loadSpotifySaved(u) }
                }
                if let f = self.pendingFav {
                    if Date() >= f.until || chosen?.key != f.key || chosen?.favorited == f.value { self.pendingFav = nil }
                    else { chosen?.favorited = f.value }
                }
                if let p = self.pendingPlay {
                    if Date() < p.until { chosen?.isPlaying = p.value } else { self.pendingPlay = nil }
                }
                self.permissionDenied = denied
                self.deniedPlayer = deniedName
                self.sampleDate = Date()
                if let old = self.info, old.key != chosen?.key { self.remember(old) }
                if self.info != chosen { self.info = chosen } else if let chosen { self.info?.position = chosen.position }
                if self.artwork !== art { self.artwork = art; self.thumbnail = art.flatMap { Self.makeThumbnail($0) } }
                if let art { self.lastArtwork = art }
                self.prepareMotion()
            }
        }
    }

    private func fetch(_ p: Player) -> (NowPlaying?, Int?) {
        let extras = p == .music ? """
            set fav to "false"
            try
                set fav to (favorited of t) as text
            end try
            set sh to "false"
            try
                set sh to (shuffle enabled) as text
            end try
            set rp to "off"
            try
                set rp to (song repeat) as text
            end try
            set bp to "0"
            try
                set bp to (bpm of t) as text
            end try
            set trackUri to ""
        """ : """
            set fav to "false"
            set sh to "false"
            set rp to "off"
            set bp to "0"
            set trackUri to ""
            try
                set trackUri to (spotify url of t)
            end try
            try
                set sh to (shuffling) as text
            end try
            try
                if repeating then set rp to "all"
            end try
        """
        let src = """
        tell application "\(p.appName)"
            set s to player state as text
            if s is "stopped" then return "stopped"
            set t to current track
            \(extras)
            return s & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (duration of t) & "|~|" & (player position) & "|~|" & fav & "|~|" & sh & "|~|" & rp & "|~|" & bp & "|~|" & trackUri
        end tell
        """
        let (d, err) = run(src)
        guard let s = d?.stringValue, s != "stopped" else { return (nil, err) }
        let f = s.components(separatedBy: "|~|")
        guard f.count == 11 else { return (nil, err) }
        func num(_ x: String) -> Double { Double(x.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let dur = p == .spotify ? num(f[4]) / 1000 : num(f[4])
        return (NowPlaying(player: p, title: f[1], artist: f[2], album: f[3], duration: dur, position: num(f[5]), isPlaying: f[0] == "playing",
                           shuffle: f[7] == "true", repeatMode: f[8], favorited: f[6] == "true", bpm: num(f[9]), uri: f[10]), nil)
    }

    private static func makeThumbnail(_ art: NSImage, px: Int = 96) -> NSImage? {
        guard let cg = art.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let w = CGFloat(cg.width), h = CGFloat(cg.height), s = max(CGFloat(px) / w, CGFloat(px) / h)   // aspect fill
        ctx.draw(cg, in: CGRect(x: (CGFloat(px) - w * s) / 2, y: (CGFloat(px) - h * s) / 2, width: w * s, height: h * s))
        return ctx.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: px / 2, height: px / 2)) }
    }

    private func fetchArtwork(_ c: NowPlaying) -> NSImage? {
        switch c.player {
        case .music:
            let (d, _) = run("tell application \"Music\" to return raw data of artwork 1 of current track")
            if let img = d.flatMap({ NSImage(data: $0.data) }) { return img }
            return (self.artTries[c.key] ?? 0) >= 2 ? MotionArt.catalogCover(artist: c.artist, title: c.title) : nil   // Music gave none
        case .spotify:
            let (d, _) = run("tell application \"Spotify\" to return artwork url of current track")
            if let s = d?.stringValue, let url = URL(string: s), let data = try? Data(contentsOf: url), let img = NSImage(data: data) { return img }
            return (self.artTries[c.key] ?? 0) >= 2 ? MotionArt.catalogCover(artist: c.artist, title: c.title) : nil
        }
    }

    private func run(_ source: String) -> (NSAppleEventDescriptor?, Int?) {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (r, err?[NSAppleScript.errorNumber] as? Int)
    }

    // MARK: Controls

    private func send(_ command: String) {
        guard let p = info?.player else { return }
        cmdQueue.async { [weak self] in
            _ = self?.run("tell application \"\(p.appName)\" to \(command)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.refresh() }
        }
    }

    private func applyPlayState(_ playing: Bool) {
        let now = Date()
        // Our own click is authoritative for ~1.2 s; Music's notices in that window are the stale echo.
        if let p = pendingPlay, p.click, now < p.until { return }
        pendingPlay = (playing, now.addingTimeInterval(0.8), false)   // also shields against stale refresh reads
        guard var i = info, i.isPlaying != playing else { return }
        if i.isPlaying { i.position += now.timeIntervalSince(sampleDate) }
        i.isPlaying = playing
        sampleDate = now
        info = i
    }

    /// Looks up the moving artwork once per album (cached). Called when the big artwork view opens.
    func loadMotionIfNeeded() {
        guard !isDemo else { return }
        guard let c = info, !c.album.isEmpty else { motionKey = ""; motionURL = nil; return }
        let k = c.artist + "|" + c.album + "|" + c.title
        guard k != motionKey else { return }
        motionKey = k; motionURL = nil
        if let cached = motionCache[k] { motionURL = cached; return }
        // remembered from an earlier run: instant, no network
        if case .some(let known) = MotionCache.get(c.artist + "|" + c.album) { motionCache[k] = .some(known); motionURL = known; return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let u = Self.lookupMotion(artist: c.artist, album: c.album, title: c.title)
            DispatchQueue.main.async {
                self?.motionCache[k] = .some(u)
                if self?.motionKey == k { self?.motionURL = u }
            }
        }
    }

    /// Finds the moving artwork and remembers the answer on disk. A "none" is only remembered when no request failed meanwhile.
    private static func lookupMotion(artist: String, album: String, title: String) -> URL? {
        let failedBefore = MotionArt.failureCount
        let u = MotionArt.find(artist: artist, album: album, title: title)
        if u != nil || MotionArt.failureCount == failedBefore { MotionCache.set(artist + "|" + album, u) }
        return u
    }

    /// Starts the lookup as soon as a song starts (not only when the lock screen opens), so the answer is ready by the time you lock.
    private func prepareMotion() {
        guard UserDefaults.standard.object(forKey: "lockScreenPlayer") as? Bool ?? true else { return }
        loadMotionIfNeeded()
    }

    func togglePlayPause() {
        guard var i = info else { return }
        let now = Date()
        if i.isPlaying { i.position += now.timeIntervalSince(sampleDate) }   // freeze the progress bar where it is
        i.isPlaying.toggle()
        sampleDate = now
        pendingPlay = (i.isPlaying, now.addingTimeInterval(1.2), true)
        info = i
        send("playpause")
    }
    func next() { send("next track") }
    func previous() { send("previous track") }
    func toggleShuffle() {
        guard let i = info else { return }
        info?.shuffle.toggle()
        send(i.player == .music ? "set shuffle enabled to \(!i.shuffle)" : "set shuffling to \(!i.shuffle)")
    }

    func cycleRepeat() {
        guard let i = info else { return }
        if i.player == .spotify {
            info?.repeatMode = i.repeatMode == "off" ? "all" : "off"
            send("set repeating to \(i.repeatMode == "off")")
        } else {
            let next = ["off": "all", "all": "one", "one": "off"][i.repeatMode] ?? "off"
            info?.repeatMode = next
            send("set song repeat to \(next)")
        }
    }

    private func remember(_ old: NowPlaying) {
        guard !old.title.isEmpty else { return }
        recentlyPlayed.removeAll { $0.title == old.title && $0.artist == old.artist }
        recentlyPlayed.insert(QueueItem(index: 0, number: 0, title: old.title, artist: old.artist, duration: old.duration, album: old.album), at: 0)
        if recentlyPlayed.count > 12 { recentlyPlayed.removeLast() }
    }

    /// With shuffle on Apple Music doesn't share what plays next, so the queue view shows what ORBT has seen play instead.
    var recent: [QueueItem] {
        recentlyPlayed.enumerated().map { QueueItem(index: 0, number: $0.offset + 1, title: $0.element.title, artist: $0.element.artist, duration: $0.element.duration, album: $0.element.album) }
    }

    private func loadSpotifySaved(_ uri: String) {
        guard !spotifyChecking.contains(uri) else { return }
        spotifyChecking.insert(uri)
        Task {
            let v = await SpotifyAPI.isSaved(uri)
            await MainActor.run {
                self.spotifyChecking.remove(uri)
                guard let v else { return }
                self.spotifySaved[uri] = v
                if self.info?.uri == uri { self.info?.favorited = v }
            }
        }
    }

    /// Apple Music: the heart. Spotify: save to / remove from the library through the Web API (only when connected in the settings).
    func toggleFavorite() {
        guard let i = info else { return }
        if i.player == .spotify {
            guard SpotifyAuth.shared.connected, !i.uri.isEmpty else { return }
            let want = !i.favorited
            spotifySaved[i.uri] = want; info?.favorited = want   // instant, like the heart
            Task {
                let ok = await SpotifyAPI.setSaved(i.uri, want)
                guard !ok else { return }
                await MainActor.run {   // Spotify said no: put it back
                    self.spotifySaved[i.uri] = !want
                    if self.info?.uri == i.uri { self.info?.favorited = !want }
                }
            }
            return
        }
        guard i.player == .music else { return }
        info?.favorited.toggle()
        pendingFav = (i.key, !i.favorited, Date().addingTimeInterval(20))
        send("set favorited of current track to \(!i.favorited)")
    }

    // MARK: Queue (Apple Music: the rest of the current playlist or album; Spotify's scripting interface has no queue)

    func loadQueue(limit: Int = 12, _ done: @escaping ([QueueItem]) -> Void) {
        if info?.player == .spotify {
            // Spotify: the real queue from the Web API, in the order it will play (shuffle included)
            guard SpotifyAuth.shared.connected else { done([]); return }
            Task {
                let items = await SpotifyAPI.queue(limit: limit)
                await MainActor.run { done(items ?? []) }
            }
            return
        }
        guard info?.player == .music else { done([]); return }
        queue.async { [weak self] in
            guard let self else { return }
            let src = """
            tell application "Music"
            set out to ""
            try
            set pl to current playlist
            set total to count of tracks of pl
            set idx to index of current track
            set endIdx to idx + \(limit)
            if endIdx > total then set endIdx to total
            repeat with i from idx + 1 to endIdx
            set t to track i of pl
            set tn to ""
            set ta to ""
            set td to 0
            set tb to ""
            try
            set tn to name of t
            set ta to artist of t
            set td to duration of t
            set tb to album of t
            end try
            set out to out & i & "|~|" & tn & "|~|" & ta & "|~|" & td & "|~|" & tb & linefeed
            end repeat
            end try
            return out
            end tell
            """
            let (r, _) = self.run(src)
            var items: [QueueItem] = []
            for line in (r?.stringValue ?? "").components(separatedBy: CharacterSet.newlines) {
                let p = line.components(separatedBy: "|~|")
                guard p.count >= 4, let idx = Int(p[0]) else { continue }
                items.append(QueueItem(index: idx, number: items.count + 1, title: p[1], artist: p[2], duration: Double(p[3].replacingOccurrences(of: ",", with: ".")) ?? 0, album: p.count > 4 ? p[4] : ""))
            }
            DispatchQueue.main.async { done(items) }
        }
    }

    func playQueueItem(_ index: Int) { send("play track \(index) of current playlist") }

    // MARK: Equalizer (Apple Music scripting exposes presets and the on/off switch, not its window)

    func loadEQ(_ done: @escaping (_ enabled: Bool, _ current: String, _ presets: [String]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let (s, _) = self.run("tell application \"Music\"\nset n to \"\"\ntry\nset n to name of current EQ preset\nend try\nreturn ((EQ enabled) as text) & \"|~|\" & n\nend tell")
            let (l, _) = self.run("tell application \"Music\" to return name of every EQ preset")
            let parts = (s?.stringValue ?? "").components(separatedBy: "|~|")
            var names: [String] = []
            if let l, l.numberOfItems > 0 { for i in 1...l.numberOfItems { if let n = l.atIndex(i)?.stringValue { names.append(n) } } }
            DispatchQueue.main.async { done(parts.first == "true", parts.count > 1 ? parts[1] : "", names) }
        }
    }

    func setEQ(enabled: Bool) {
        queue.async { [weak self] in _ = self?.run("tell application \"Music\" to set EQ enabled to \(enabled)") }
    }

    func setEQPreset(_ name: String) {
        queue.async { [weak self] in
            _ = self?.run("tell application \"Music\"\nset EQ enabled to true\nset current EQ preset to EQ preset \"\(name)\"\nend tell")
        }
    }

    func seek(to seconds: Double) {
        info?.position = seconds
        sampleDate = Date()
        send("set player position to \(seconds)")
    }
}
