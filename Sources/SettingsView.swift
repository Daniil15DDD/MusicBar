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
    @AppStorage("lockClockWeight") private var lockClockWeight = "light"
    @AppStorage("lockClockScale") private var lockClockScale = 1.0
    @AppStorage("tintLyrics") private var tintLyrics = false
    @AppStorage("showLyricsButton") private var showLyricsButton = true
    @AppStorage("showQueueButton") private var showQueueButton = true
    @AppStorage("spotifyClientID") private var spotifyClientID = ""
    @ObservedObject private var spotify = SpotifyAuth.shared
    @StateObject private var loginBox = Local(SMAppService.mainApp.status == .enabled)
    private var launchAtLogin: Bool { get { loginBox.v } nonmutating set { loginBox.v = newValue } }
    @StateObject private var errBox = Local<String?>(nil)
    private var loginError: String? { get { errBox.v } nonmutating set { errBox.v = newValue } }

    /// Every setting has an ⓘ: click it to see what the setting does and a little picture of each choice.
    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: $loginBox.v) { InfoLabel("Launch at login", .launchAtLogin) }
                    .onChange(of: loginBox.v) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Picker(selection: $preferredPlayer) {
                    Text("Automatic").tag("auto")
                    Text("Apple Music").tag("music")
                    Text("Spotify").tag("spotify")
                } label: { InfoLabel("Player", .player) }
                Toggle(isOn: $openPopoverOnClick) { InfoLabel("Open the player on click", .popoverClick) }
            }
            Section("Menu bar") {
                Toggle(isOn: $showArtwork) { InfoLabel("Album artwork", .artwork) }
                Toggle(isOn: $showWaveform) { InfoLabel("Animated waveform", .waveform) }
                Toggle(isOn: $reactiveAudio) { InfoLabel("Waveform follows the music", .reactiveAudio) }.disabled(!showWaveform)
                Picker(selection: $fallback) {
                    Text("Music note").tag("icon")
                    Text("Last album cover").tag("lastArtwork")
                    Text("Hidden").tag("hidden")
                } label: { InfoLabel("When nothing is playing", .fallback) }
            }
            Section("Lock screen") {
                Toggle(isOn: $lockScreenPlayer) { InfoLabel("Player on the lock screen", .lockPlayer) }
                Toggle(isOn: $lockLiquidGlass) { InfoLabel("Liquid Glass card", .glass) }.disabled(!lockScreenPlayer)
            }
            Section {
                Toggle(isOn: $showLyricsButton) { InfoLabel("Lyrics button", .lyricsButton) }
                Toggle(isOn: $tintLyrics) { InfoLabel("Tint lyrics with the song's colour", .tintLyrics) }
                Toggle(isOn: $showQueueButton) { InfoLabel("Queue button", .queueButton) }
                Picker(selection: $lockContrast) {
                    Text("Automatic").tag("auto")
                    Text("High").tag("high")
                    Text("Off").tag("off")
                } label: { InfoLabel("Contrast", .contrast) }
                Picker(selection: $lockClockStyle) {
                    Text("Serif").tag("serif")
                    Text("Sans").tag("sans")
                    Text("Rounded").tag("rounded")
                    Text("Mono").tag("mono")
                    Text("Cooper Black").tag("cooper")
                    Text("Zapfino").tag("zapfino")
                    Text("Blackmoor").tag("blackmoor")
                } label: { InfoLabel("Clock style", .clockStyle) }
                Picker(selection: $lockClockWeight) {
                    Text("Ultra light").tag("ultralight")
                    Text("Light").tag("light")
                    Text("Regular").tag("regular")
                    Text("Bold").tag("bold")
                } label: { InfoLabel("Clock weight", .clockWeight) }
                Slider(value: $lockClockScale, in: 0.6...1.4) { InfoLabel("Clock size", .clockSize) }
            } header: {
                Text("Full-screen lock screen")
            } footer: {
                Text("Click the cover on the lock screen card to open it.").font(.caption)
            }
            .disabled(!lockScreenPlayer)
            Section {
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
                Link("Open the Spotify developer dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!).font(.caption)
            } header: {
                HStack(spacing: 6) { Text("Spotify (optional)"); InfoButton(info: .spotify) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 720)
    }
}
