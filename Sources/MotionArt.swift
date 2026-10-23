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
            let pages = list.filter { !tried.contains($0) }.prefix(6).compactMap { URL(string: $0) }
            tried.formUnion(pages.map { $0.absoluteString })
            // each album page is ~0.5 MB: fetch them three at a time instead of one after the other, then take the first in order
            for batch in stride(from: 0, to: pages.count, by: 3) {
                for data in fetchMany(Array(pages[batch..<min(batch + 3, pages.count)])) {
                    guard let html = data.flatMap({ String(data: $0, encoding: .utf8) }) else { continue }
                    if let v = video(in: html, key: "motionDetailSquare") ?? video(in: html, key: "motionDetailTall") { return v }
                }
            }
            return nil
        }

        // 1) albums matching the name, 2) the song's own releases (both searches at the same time)
        var albumHits: [[String: Any]] = [], songHits: [[String: Any]] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { i in
            let r = i == 0 ? search("\(artist) \(album)", "album") : search("\(artist) \(title)", "song")
            lock.lock(); if i == 0 { albumHits = r } else { songHits = r }; lock.unlock()
        }
        for r in albumHits where similarAlbum(r) && sameArtist(r) { add(r) }
        for r in songHits where norm(r["trackName"] as? String ?? "") == norm(title) && sameArtist(r) { add(r) }
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

    /// Network requests that failed so far. A lookup that found nothing while this went up must not be remembered as "has no moving artwork".
    private static let failLock = NSLock()
    private static var failures = 0
    static var failureCount: Int { failLock.lock(); defer { failLock.unlock() }; return failures }

    private static func fetch(_ url: URL) -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        URLSession.shared.dataTask(with: req) { d, _, _ in out = d; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 10)
        if out == nil { failLock.lock(); failures += 1; failLock.unlock() }
        return out
    }

    /// Several downloads at the same time; the results come back in the order of `urls`.
    private static func fetchMany(_ urls: [URL]) -> [Data?] {
        var out = [Data?](repeating: nil, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            let d = fetch(urls[i])
            lock.lock(); out[i] = d; lock.unlock()
        }
        return out
    }
}

/// Remembers which album has which moving artwork, so the lookup happens once per album, even across launches.
/// Tiny: only the video addresses (a few KB in the Caches folder), never the videos. "No moving artwork" is remembered for 6 hours
/// (Apple adds covers over time), an address for 60 days.
enum MotionCache {
    private static let queue = DispatchQueue(label: "orbt.motioncache")
    private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ORBT-motion.json")
    private static var entries: [String: [String: Any]] = {
        (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] } ?? [:]
    }()

    /// nil = not known yet; .some(nil) = known to have none; .some(url) = known address.
    static func get(_ key: String) -> URL?? {
        queue.sync {
            guard let e = entries[key], let t = e["date"] as? Double else { return nil }
            let age = Date().timeIntervalSince1970 - t
            if let s = e["url"] as? String, !s.isEmpty { return age < 60 * 86400 ? .some(URL(string: s)) : nil }
            return age < 6 * 3600 ? .some(nil) : nil
        }
    }

    static func set(_ key: String, _ url: URL?) {
        queue.sync {
            entries[key] = ["url": url?.absoluteString ?? "", "date": Date().timeIntervalSince1970]
            if entries.count > 500 { entries = entries.filter { ($0.value["date"] as? Double ?? 0) > Date().timeIntervalSince1970 - 30 * 86400 } }
            if let d = try? JSONSerialization.data(withJSONObject: entries) { try? d.write(to: file, options: .atomic) }
        }
    }
}

/// Remembers which version of a stream was chosen from its master playlist, so the playlist is downloaded once per video.
/// (A look-ahead that kept the NEXT song's clip buffered was tried and removed: ~23 MB per clip, and with shuffle on the next song is unknown.)
final class MotionStreams {
    static let shared = MotionStreams()
    private var variants: [String: URL] = [:]      // main thread only; master playlist -> the version chosen from it (a few bytes each)

    private func key(_ u: URL, _ px: CGFloat) -> String { "\(u.absoluteString)|\(Int(px))" }

    /// The sharpest version of the stream up to `maxPixels`; the playlist is downloaded only once per video.
    func variant(for u: URL, maxPixels: CGFloat, _ done: @escaping (URL?) -> Void) {
        if let v = variants[key(u, maxPixels)] { done(v); return }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let v = LoopingPlayerView.bestVariant(in: text, base: u, maxPixels: maxPixels)
            DispatchQueue.main.async {
                if let v { if self.variants.count > 50 { self.variants = [:] }; self.variants[self.key(u, maxPixels)] = v }
                done(v)
            }
        }.resume()
    }

    static func makeItem(_ source: URL, maxPixels: CGFloat) -> AVPlayerItem {
        let item = AVPlayerItem(url: source)
        item.preferredMaximumResolution = CGSize(width: maxPixels, height: maxPixels)
        item.preferredForwardBufferDuration = 15   // the whole loop
        return item
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
        MotionStreams.shared.variant(for: u, maxPixels: maxPixels) { [weak self] v in
            guard let self, self.url == u else { return }   // a newer load() or a stop() superseded this one
            self.start(v ?? u)
        }
    }

    private func start(_ source: URL) {
        let item = MotionStreams.makeItem(source, maxPixels: maxPixels)
        observeEnd(item)
        player.replaceCurrentItem(with: item)
        if shouldPlay { player.play() } else { player.pause() }
    }

    private func observeEnd(_ item: AVPlayerItem?) {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        guard let item else { return }
        observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero); self?.player.play()
        }
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
