import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showWaveform") private var showWaveform = true
    @AppStorage("showArtwork") private var showArtwork = true
    @AppStorage("preferredPlayer") private var preferredPlayer = "auto"
    @AppStorage("openPopoverOnClick") private var openPopoverOnClick = true
    @AppStorage("fallback") private var fallback = "icon"
    @AppStorage("reactiveAudio") private var reactiveAudio = false
    @AppStorage("lockScreenPlayer") private var lockScreenPlayer = true
    @AppStorage("lockLiquidGlass") private var lockLiquidGlass = true
    @AppStorage("lockContrast") private var lockContrast = "auto"
    @AppStorage("lockClockStyle") private var lockClockStyle = "serif"
    @AppStorage("tintLyrics") private var tintLyrics = false
    @AppStorage("showLyricsButton") private var showLyricsButton = true
    @AppStorage("showQueueButton") private var showQueueButton = true
    @AppStorage("spotifyClientID") private var spotifyClientID = ""
    @ObservedObject private var spotify = SpotifyAuth.shared
    @StateObject private var loginBox = Local(SMAppService.mainApp.status == .enabled)
    private var launchAtLogin: Bool { get { loginBox.v } nonmutating set { loginBox.v = newValue } }
    @StateObject private var errBox = Local<String?>(nil)
    private var loginError: String? { get { errBox.v } nonmutating set { errBox.v = newValue } }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $loginBox.v)
                    .onChange(of: loginBox.v) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Menu bar") {
                Toggle("Show album artwork", isOn: $showArtwork)
                Toggle("Show animated waveform", isOn: $showWaveform)
                Toggle("Make waveform react to the audio", isOn: $reactiveAudio)
                Text("Off: bars move randomly like Boring Notch. On: reads live system audio levels, which makes macOS ask for audio-capture permission. Nothing is recorded or stored.").font(.caption).foregroundStyle(.secondary)
                Picker("When nothing is playing", selection: $fallback) {
                    Text("Music note icon").tag("icon")
                    Text("Last album artwork").tag("lastArtwork")
                    Text("Hide item").tag("hidden")
                }
            }
            Section("Behaviour") {
                Toggle("Show the player on the lock screen", isOn: $lockScreenPlayer)
                Toggle("Liquid Glass look on the lock screen", isOn: $lockLiquidGlass).disabled(!lockScreenPlayer)
                Picker("Contrast on the full-screen lock screen", selection: $lockContrast) {
                    Text("Automatic").tag("auto")
                    Text("Off").tag("off")
                    Text("High").tag("high")
                }.disabled(!lockScreenPlayer)
                Picker("Clock style on the full-screen lock screen", selection: $lockClockStyle) {
                    Text("Serif").tag("serif")
                    Text("Sans").tag("sans")
                    Text("Rounded").tag("rounded")
                    Text("Mono").tag("mono")
                }.disabled(!lockScreenPlayer)
                Text("Automatic: on a bright cover (a white album, say) the clock and buttons take the cover's own colour, darkened (brown for a brown baby), or near-black if it has none. High keeps white text and always darkens the picture. Off never changes anything.").font(.caption).foregroundStyle(.secondary)
                Toggle("Lyrics button on the full-screen lock screen", isOn: $showLyricsButton).disabled(!lockScreenPlayer)
                Toggle("Tint the lyrics with the song's colour", isOn: $tintLyrics).disabled(!lockScreenPlayer)
                Toggle("Queue button on the full-screen lock screen", isOn: $showQueueButton).disabled(!lockScreenPlayer)
                Text("Lyrics are looked up on lrclib.net, which receives the song title, artist and length. The queue shows the next songs of the current Apple Music playlist (with shuffle on Apple Music hides what is next, so the songs you just played are shown), or Spotify's real queue once Spotify is connected below.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open player popover on click", isOn: $openPopoverOnClick)
                Text("When off, a click toggles play/pause. Right-click always opens the menu.").font(.caption).foregroundStyle(.secondary)
                Picker("Player", selection: $preferredPlayer) {
                    Text("Automatic").tag("auto")
                    Text("Apple Music").tag("music")
                    Text("Spotify").tag("spotify")
                }
            }
            Section("Spotify (optional)") {
                if spotify.connected {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect") { spotify.disconnect() }
                    }
                } else {
                    TextField("Client ID", text: $spotifyClientID)
                    Button("Connect Spotify") { spotify.connect() }.disabled(spotifyClientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !spotify.status.isEmpty { Text(spotify.status).font(.caption).foregroundStyle(.secondary) }
                Text("Adds Spotify's real queue and a save button (the plus / green tick). Spotify requires your own free developer app, and its owner needs Premium: create one, add the redirect URI http://127.0.0.1/callback, and paste its Client ID here. ORBT logs in once in your browser and keeps the token in the Keychain.").font(.caption).foregroundStyle(.secondary)
                Link("Open the Spotify developer dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!).font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 880)
    }
}
