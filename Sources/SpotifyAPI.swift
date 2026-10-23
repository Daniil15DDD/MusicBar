import AppKit
import CryptoKit
import Network
import Security

/// Spotify's scripting interface has no queue and no like command, so those come from Spotify's own Web API.
/// Spotify's 2026 rules for such apps: each user registers their own free developer app (the owner needs Premium, up to 5 users),
/// pastes its Client ID into ORBT's settings and logs in once. The login is OAuth with PKCE (no client secret anywhere): the browser
/// is sent back to a one-time listener on 127.0.0.1, and the tokens are kept in the macOS Keychain.
final class SpotifyAuth: ObservableObject {
    static let shared = SpotifyAuth()
    @Published private(set) var connected: Bool
    @Published private(set) var status = ""

    /// Scopes Spotify lists for the queue and for the library calls (its generic library endpoints ask for the follow and playlist ones too).
    private let scopes = "user-read-playback-state user-read-currently-playing user-library-read user-library-modify user-follow-read user-follow-modify playlist-read-private playlist-modify-public"
    private var listener: NWListener?
    private var verifier = "", state = "", redirect = ""

    var clientID: String { (UserDefaults.standard.string(forKey: "spotifyClientID") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private init() { connected = Keychain.get("spotify-refresh") != nil }

    // MARK: Login

    func connect() {
        guard !clientID.isEmpty else { set(status: "Paste your Client ID first"); return }
        listener?.cancel()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)   // loopback only: nothing else on the network can reach it
        guard let l = try? NWListener(using: params) else { set(status: "Couldn't start the login listener"); return }
        listener = l
        verifier = Self.random(64); state = Self.random(24)
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.stateUpdateHandler = { [weak self, weak l] st in
            switch st {
            case .ready: if let port = l?.port?.rawValue { DispatchQueue.main.async { self?.openLogin(port: port) } }
            case .failed: DispatchQueue.main.async { self?.set(status: "Couldn't start the login listener") }
            default: break
            }
        }
        l.start(queue: .main)
        set(status: "Waiting for you to log in in the browser…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self, weak l] in
            guard let self, let l, self.listener === l else { return }
            l.cancel(); self.listener = nil
            if !self.connected { self.set(status: "Login timed out. Try again.") }
        }
    }

    func disconnect() {
        Keychain.delete("spotify-access"); Keychain.delete("spotify-refresh")
        UserDefaults.standard.removeObject(forKey: "spotifyExpiry")
        DispatchQueue.main.async { self.connected = false; self.status = "" }
    }

    private func openLogin(port: UInt16) {
        redirect = "http://127.0.0.1:\(port)/callback"
        let challenge = Self.challenge(for: verifier)
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [.init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"), .init(name: "redirect_uri", value: redirect),
                        .init(name: "scope", value: scopes), .init(name: "state", value: state),
                        .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge)]
        if let u = c.url { openURL(u) }
    }

    /// Opens the login page; replaceable so the flow can be tested without a browser.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// PKCE: base64url(SHA-256(verifier)) without padding.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// The browser comes back with ?code=...&state=...; only the exact path and our own state are accepted.
    private func handle(_ c: NWConnection) {
        c.start(queue: .main)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let req = String(data: data, encoding: .utf8) else { c.cancel(); return }
            let target = (req.components(separatedBy: "\r\n").first ?? "").split(separator: " ")
            guard target.count >= 2, let comps = URLComponents(string: "http://127.0.0.1" + target[1]), comps.path == "/callback" else {
                Self.respond(c, "Not found", ok: false); return
            }
            var q: [String: String] = [:]
            for i in comps.queryItems ?? [] { q[i.name] = i.value ?? "" }
            let good = q["state"] == self.state && q["code"] != nil
            Self.respond(c, good ? "ORBT is connected to Spotify. You can close this tab." : "Spotify login was cancelled. You can close this tab.", ok: good)
            self.listener?.cancel(); self.listener = nil
            if good, let code = q["code"] { Task { await self.exchange(code) } } else { self.set(status: "Login was cancelled") }
        }
    }

    private static func respond(_ c: NWConnection, _ text: String, ok: Bool) {
        let body = "<html><body style=\"font-family:-apple-system;text-align:center;margin-top:20vh\"><h2>\(text)</h2></body></html>"
        let head = "HTTP/1.1 \(ok ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        c.send(content: Data((head + body).utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: Tokens

    private func exchange(_ code: String) async {
        let ok = await token(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "client_id": clientID, "code_verifier": verifier])
        set(status: ok ? "Connected" : "Spotify refused the login. Check the Client ID and the redirect URI.", connected: ok)
    }

    /// POSTs to Spotify's token endpoint and stores what comes back.
    private func token(_ form: [String: String]) async -> Bool {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return false }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 15
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        r.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let access = o["access_token"] as? String else { return false }
        Keychain.set(access, "spotify-access")
        if let refresh = o["refresh_token"] as? String { Keychain.set(refresh, "spotify-refresh") }
        UserDefaults.standard.set(Date().timeIntervalSince1970 + (o["expires_in"] as? Double ?? 3600), forKey: "spotifyExpiry")
        return true
    }

    /// A valid access token, refreshed when it is about to expire; nil when not connected.
    func accessToken(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh, let t = Keychain.get("spotify-access"), Date().timeIntervalSince1970 < UserDefaults.standard.double(forKey: "spotifyExpiry") - 60 { return t }
        guard let refresh = Keychain.get("spotify-refresh") else { return nil }
        if await token(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID]) { return Keychain.get("spotify-access") }
        return nil
    }

    private func set(status s: String, connected c: Bool? = nil) {
        DispatchQueue.main.async { self.status = s; if let c { self.connected = c } }
    }

    private static func random(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var g = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in chars[Int(g.next() % UInt64(chars.count))] })
    }
}

enum SpotifyAPI {
    private static func request(_ method: String, _ path: String, query: String = "", retry: Bool = true) async -> (Data?, Int?) {
        guard let token = await SpotifyAuth.shared.accessToken(forceRefresh: !retry),
              let url = URL(string: "https://api.spotify.com/v1" + path + (query.isEmpty ? "" : "?" + query)) else { return (nil, nil) }
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 10
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (d, resp) = try? await URLSession.shared.data(for: r), let code = (resp as? HTTPURLResponse)?.statusCode else { return (nil, nil) }
        if code == 401 && retry { return await request(method, path, query: query, retry: false) }   // the token was rejected: refresh once
        return (d, code)
    }

    private static func encoded(_ uri: String) -> String { "uris=" + (uri.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? uri) }

    /// The songs after the current one, in the order Spotify will actually play them (shuffle included). nil = not available.
    static func queue(limit: Int) async -> [QueueItem]? {
        let (d, code) = await request("GET", "/me/player/queue")
        guard code == 200, let d, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let list = o["queue"] as? [[String: Any]] else { return nil }
        var out: [QueueItem] = []
        for t in list {
            guard let name = t["name"] as? String else { continue }
            let artist = ((t["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            let album = ((t["album"] as? [String: Any])?["name"] as? String) ?? ""
            out.append(QueueItem(index: out.count + 1, number: out.count + 1, title: name, artist: artist, duration: (t["duration_ms"] as? Double ?? 0) / 1000, album: album))
            if out.count >= limit { break }
        }
        return out
    }

    static func isSaved(_ uri: String) async -> Bool? {
        let (d, code) = await request("GET", "/me/library/contains", query: encoded(uri))
        guard code == 200, let d, let a = (try? JSONSerialization.jsonObject(with: d)) as? [Bool] else { return nil }
        return a.first
    }

    static func setSaved(_ uri: String, _ saved: Bool) async -> Bool {
        let (_, code) = await request(saved ? "PUT" : "DELETE", "/me/library", query: encoded(uri))
        return code == 200
    }
}

/// Tokens are secrets: they live in the Keychain, not in the preferences.
private enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ORBT", kSecAttrAccount as String: account]
    }
    static func set(_ value: String, _ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account); q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ account: String) -> String? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}
