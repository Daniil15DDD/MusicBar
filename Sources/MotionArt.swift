import SwiftUI
import AVFoundation

/// Finds Apple Music's own moving artwork (square loop) for an album.
/// shortcut: scrapes Apple's public album page (unofficial), so it can break if the page layout changes; returns nil then.
enum MotionArt {
    /// Your Apple Music storefront (e.g. "au"); catalogues differ per country, so it is tried before the US one.
    private static var storefront: String { Locale.current.region?.identifier.lowercased() ?? "us" }

    /// Cover from Apple's catalogue, used when Music itself gives no artwork for the song.
    static func catalogCover(artist: String, title: String) -> NSImage? {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let wantA = norm(artist), wantT = norm(title)
        for country in (storefront == "us" ? ["us"] : [storefront, "us"]) {
            guard let t = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let u = URL(string: "https://itunes.apple.com/search?term=\(t)&entity=song&limit=10&country=\(country)"),
                  let d = fetch(u),
                  let r = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["results"] as? [[String: Any]] else { continue }
            guard let hit = r.first(where: { x in
                      let a = norm(x["artistName"] as? String ?? "")
                      return norm(x["trackName"] as? String ?? "") == wantT && (a.contains(wantA) || wantA.contains(a))
                  }),
                  let art = hit["artworkUrl100"] as? String,
                  let url = URL(string: art.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")),
                  let data = fetch(url), let img = NSImage(data: data) else { continue }
            return img
        }
        return nil
    }

    /// Tries your storefront first, then the US one.
    static func find(artist: String, album: String, title: String) -> URL? {
        for country in (storefront == "us" ? ["us"] : [storefront, "us"]) {
            if let v = find(in: country, artist: artist, album: album, title: title) { return v }
        }
        return nil
    }

    /// Finds the moving artwork for the song's EXACT album: an edition with the same name wins over similar ones
    /// ("2 Alivë (Geëk Pack)" is not "2 Alivë"). Prefers the square loop, falls back to the tall one.
    private static func find(in country: String, artist: String, album: String, title: String) -> URL? {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        func search(_ term: String, _ entity: String) -> [[String: Any]] {
            guard let t = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let u = URL(string: "https://itunes.apple.com/search?term=\(t)&entity=\(entity)&limit=10&country=\(country)"),
                  let d = fetch(u),
                  let r = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
            return r
        }
        let wantAlbum = norm(album), wantArtist = norm(artist)
        var exact: [String] = [], loose: [String] = []   // album pages: same name / similar name
        func add(_ r: [String: Any]) {
            guard let p = r["collectionViewUrl"] as? String, !exact.contains(p), !loose.contains(p) else { return }
            if norm(r["collectionName"] as? String ?? "") == wantAlbum { exact.append(p) } else { loose.append(p) }
        }
        func sameArtist(_ r: [String: Any]) -> Bool {
            let a = norm(r["artistName"] as? String ?? "")
            return a.contains(wantArtist) || wantArtist.contains(a)
        }
        func similarAlbum(_ r: [String: Any]) -> Bool {
            let n = norm(r["collectionName"] as? String ?? "")
            return !wantAlbum.isEmpty && !n.isEmpty && (n.contains(wantAlbum) || wantAlbum.contains(n))
        }
        var tried = Set<String>()
        func firstMotion(_ list: [String]) -> URL? {
            for page in list.filter({ !tried.contains($0) }).prefix(6) {
                tried.insert(page)
                guard let u = URL(string: page), let html = fetch(u).flatMap({ String(data: $0, encoding: .utf8) }) else { continue }
                if let v = video(in: html, key: "motionDetailSquare") ?? video(in: html, key: "motionDetailTall") { return v }
            }
            return nil
        }

        // 1) albums matching the name, 2) the song's own releases
        for r in search("\(artist) \(album)", "album") where similarAlbum(r) && sameArtist(r) { add(r) }
        for r in search("\(artist) \(title)", "song") where norm(r["trackName"] as? String ?? "") == norm(title) && sameArtist(r) { add(r) }
        if let v = firstMotion(exact) { return v }
        // 3) the artist's whole catalogue: the search API misses many releases and same-named editions, but the artist lookup lists them
        for a in search(artist, "musicArtist") where norm(a["artistName"] as? String ?? "") == wantArtist {
            guard let id = a["artistId"] as? Int, let u = URL(string: "https://itunes.apple.com/lookup?id=\(id)&entity=album&limit=200&country=\(country)"),
                  let d = fetch(u),
                  let r = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["results"] as? [[String: Any]] else { continue }
            r.filter(similarAlbum).forEach(add)
            break
        }
        // Same-named editions are the right ones. Only if the album has no exact page at all do similar editions count.
        let result = firstMotion(exact) ?? (exact.isEmpty ? firstMotion(loose) : nil)
        return result
    }

    private static func video(in html: String, key: String) -> URL? {
        guard let re = try? NSRegularExpression(pattern: "\"\(key)\"\\s*:\\s*\\{.*?\"video\"\\s*:\\s*\"(https:[^\"]+\\.m3u8)\"", options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return URL(string: String(html[r]))
    }

    private static func fetch(_ url: URL) -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        URLSession.shared.dataTask(with: req) { d, _, _ in out = d; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return out
    }
}

/// Muted, looping video; capped at 720p so it stays light. Only exists while the big view is on screen.
struct LoopingVideo: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> LoopingPlayerView { let v = LoopingPlayerView(); v.play(url); return v }
    func updateNSView(_ v: LoopingPlayerView, context: Context) { if v.url != url { v.play(url) } }
    static func dismantleNSView(_ v: LoopingPlayerView, coordinator: ()) { v.stop() }
}

final class LoopingPlayerView: NSView {
    private(set) var url: URL?
    /// Widest version of the video to use. Small views stay light (960); the lock screen backdrop asks for up to 1920.
    var maxPixels: CGFloat = 960
    private let player = AVPlayer()
    private var observer: NSObjectProtocol?
    private var shouldPlay = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer = layer
        wantsLayer = true
        player.isMuted = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func play(_ u: URL) { load(u); resume() }
    func resume() { shouldPlay = true; player.play() }
    func pause() { shouldPlay = false; player.pause() }

    /// Starts buffering without playing, so a later resume() starts almost instantly.
    /// The stream normally starts at its smallest version and only climbs after a few seconds, which looked blurry,
    /// so the sharpest version up to `maxPixels` is chosen from the playlist up front.
    func load(_ u: URL) {
        stop()
        url = u
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            DispatchQueue.main.async {
                guard let self, self.url == u else { return }   // a newer load() or a stop() superseded this one
                self.start(LoopingPlayerView.bestVariant(in: text, base: u, maxPixels: self.maxPixels) ?? u)
            }
        }.resume()
    }

    private func start(_ source: URL) {
        let item = AVPlayerItem(url: source)
        item.preferredMaximumResolution = CGSize(width: maxPixels, height: maxPixels)
        observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero); self?.player.play()
        }
        player.replaceCurrentItem(with: item)
        if shouldPlay { player.play() } else { player.pause() }
    }

    /// From a master playlist: the widest version not wider than `maxPixels`, and among those the highest bitrate.
    static func bestVariant(in text: String, base: URL, maxPixels: CGFloat) -> URL? {
        func number(after key: String, in line: String) -> Int? {
            guard let r = line.range(of: key) else { return nil }
            return Int(line[r.upperBound...].prefix(while: { $0.isNumber }))
        }
        let lines = text.components(separatedBy: .newlines)
        var best: (width: Int, bandwidth: Int, url: URL)?
        for (i, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") && i + 1 < lines.count {
            guard let w = number(after: "RESOLUTION=", in: line), CGFloat(w) <= maxPixels,
                  let u = URL(string: lines[i + 1].trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL else { continue }
            let bw = number(after: ",BANDWIDTH=", in: line) ?? 0
            if best == nil || w > best!.width || (w == best!.width && bw > best!.bandwidth) { best = (w, bw, u) }
        }
        return best?.url
    }

    func stop() {
        shouldPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        url = nil
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
    }
}
