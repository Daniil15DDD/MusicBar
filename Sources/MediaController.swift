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
    /// Stable per-track number used to seed the pulse pattern.
    var seed: Int { key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } }
    var key: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

/// Reads Music/Spotify through AppleScript (public, no private APIs).
/// Updates are event-driven (distributed notifications) plus a slow safety poll.
final class MediaController: ObservableObject {
    @Published private(set) var info: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lastArtwork: NSImage?
    @Published private(set) var permissionDenied = false
    /// Wall-clock moment `info.position` was sampled, used to interpolate the progress bar.
    private(set) var sampleDate = Date()

    private let queue = DispatchQueue(label: "musicbar.media")
    private var artCache: [String: NSImage] = [:]   // queue-confined
    private var artKey = ""                          // queue-confined
    /// Play state we set on click; stale refreshes are ignored until it expires so the UI never flips back.
    private var pendingPlay: (value: Bool, until: Date, click: Bool)?
    private var timer: Timer?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// Static instance for rendering README images (`--render`); no observers or timers.
    init(demo: NowPlaying, artwork: NSImage) {
        info = demo
        self.artwork = artwork
        lastArtwork = artwork
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
            var candidates: [NowPlaying] = []
            for p in Player.allCases where preferred == "auto" || preferred == p.rawValue {
                guard !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty else { continue }
                let (np, err) = self.fetch(p)
                if err == -1743 { denied = true }
                if let np { candidates.append(np) }
            }
            let chosen = candidates.first(where: { $0.isPlaying }) ?? candidates.first
            var art: NSImage?
            if let c = chosen {
                if c.key != self.artKey {
                    self.artKey = c.key
                    if self.artCache[c.key] == nil, let img = self.fetchArtwork(c) { self.artCache[c.key] = img }
                    if self.artCache.count > 20 { self.artCache = self.artCache.filter { $0.key == c.key } }
                }
                art = self.artCache[c.key]
            }
            DispatchQueue.main.async {
                var chosen = chosen
                if let p = self.pendingPlay {
                    if Date() < p.until { chosen?.isPlaying = p.value } else { self.pendingPlay = nil }
                }
                self.permissionDenied = denied
                self.sampleDate = Date()
                if self.info != chosen { self.info = chosen } else if let chosen { self.info?.position = chosen.position }
                if self.artwork !== art { self.artwork = art }
                if let art { self.lastArtwork = art }
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
        """ : """
            set fav to "false"
            set sh to "false"
            set rp to "off"
            set bp to "0"
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
            return s & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (duration of t) & "|~|" & (player position) & "|~|" & fav & "|~|" & sh & "|~|" & rp & "|~|" & bp
        end tell
        """
        let (d, err) = run(src)
        guard let s = d?.stringValue, s != "stopped" else { return (nil, err) }
        let f = s.components(separatedBy: "|~|")
        guard f.count == 10 else { return (nil, err) }
        func num(_ x: String) -> Double { Double(x.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let dur = p == .spotify ? num(f[4]) / 1000 : num(f[4])
        return (NowPlaying(player: p, title: f[1], artist: f[2], album: f[3], duration: dur, position: num(f[5]), isPlaying: f[0] == "playing",
                           shuffle: f[7] == "true", repeatMode: f[8], favorited: f[6] == "true", bpm: num(f[9])), nil)
    }

    private func fetchArtwork(_ c: NowPlaying) -> NSImage? {
        switch c.player {
        case .music:
            let (d, _) = run("tell application \"Music\" to return raw data of artwork 1 of current track")
            return d.flatMap { NSImage(data: $0.data) }
        case .spotify:
            let (d, _) = run("tell application \"Spotify\" to return artwork url of current track")
            guard let s = d?.stringValue, let url = URL(string: s), let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
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
        queue.async { [weak self] in
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

    /// Apple Music only; Spotify's scripting interface has no like/favourite command.
    func toggleFavorite() {
        guard let i = info, i.player == .music else { return }
        info?.favorited.toggle()
        send("set favorited of current track to \(!i.favorited)")
    }

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
