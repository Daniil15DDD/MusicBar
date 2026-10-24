import SwiftUI
import ServiceManagement

/// Four tabs, a few short rows each, an icon on every row. Everything longer lives behind the row's ⓘ.
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

    @AppStorage("settingsTab") private var tab = 0   // also remembers the last tab you were on
    private let tabs = [("General", "gearshape"), ("Menu bar", "menubar.rectangle"), ("Lock screen", "lock"), ("Spotify", "dot.radiowaves.left.and.right")]

    var body: some View {
        VStack(spacing: 0) {
            // our own icon tab bar: the stock macOS TabView draws text-only tabs inside a box
            HStack(spacing: 6) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button { tab = i } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tabs[i].1).font(.system(size: 19, weight: .regular)).frame(height: 24)
                            Text(tabs[i].0).font(.caption)
                        }
                        .frame(width: 88, height: 52)
                        .foregroundStyle(tab == i ? Color.accentColor : Color.secondary)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tab == i ? Color.accentColor.opacity(0.16) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            Divider()
            Group {
                switch tab {
                case 1: menuBar
                case 2: lockScreen
                case 3: spotifyTab
                default: general
                }
            }
        }
        .frame(width: 440, height: 580)
    }

    var general: some View {
        Form {
            Section {
                Toggle(isOn: $loginBox.v) { InfoLabel("Launch at login", .launchAtLogin, icon: "power") }
                    .onChange(of: loginBox.v) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Picker(selection: $preferredPlayer) {
                    Text("Auto").tag("auto")
                    Text("Apple Music").tag("music")
                    Text("Spotify").tag("spotify")
                } label: { InfoLabel("Player", .player, icon: "music.note") }
                Toggle(isOn: $openPopoverOnClick) { InfoLabel("Click opens player", .popoverClick, icon: "cursorarrow.click") }
            }
        }
        .formStyle(.grouped)
    }

    var menuBar: some View {
        Form {
            Section {
                Toggle(isOn: $showArtwork) { InfoLabel("Artwork", .artwork, icon: "photo") }
                Toggle(isOn: $showWaveform) { InfoLabel("Waveform", .waveform, icon: "waveform") }
                Toggle(isOn: $reactiveAudio) { InfoLabel("Reacts to audio", .reactiveAudio, icon: "speaker.wave.2") }.disabled(!showWaveform)
                Picker(selection: $fallback) {
                    Text("Note").tag("icon")
                    Text("Last cover").tag("lastArtwork")
                    Text("Hidden").tag("hidden")
                } label: { InfoLabel("When idle", .fallback, icon: "pause.circle") }
            }
        }
        .formStyle(.grouped)
    }

    var lockScreen: some View {
        Form {
            Section {
                Toggle(isOn: $lockScreenPlayer) { InfoLabel("Show player", .lockPlayer, icon: "rectangle.on.rectangle") }
                Toggle(isOn: $lockLiquidGlass) { InfoLabel("Glass card", .glass, icon: "square.on.square") }.disabled(!lockScreenPlayer)
            }
            Section("Full screen") {
                Toggle(isOn: $showLyricsButton) { InfoLabel("Lyrics", .lyricsButton, icon: "quote.bubble") }
                Toggle(isOn: $tintLyrics) { InfoLabel("Colour lyrics", .tintLyrics, icon: "paintpalette") }.disabled(!showLyricsButton)
                Toggle(isOn: $showQueueButton) { InfoLabel("Queue", .queueButton, icon: "list.bullet") }
                Picker(selection: $lockContrast) {
                    Text("Auto").tag("auto")
                    Text("High").tag("high")
                    Text("Off").tag("off")
                } label: { InfoLabel("Contrast", .contrast, icon: "circle.lefthalf.filled") }
            }
            .disabled(!lockScreenPlayer)
            Section("Clock") {
                Picker(selection: $lockClockStyle) {
                    Text("Serif").tag("serif")
                    Text("Sans").tag("sans")
                    Text("Rounded").tag("rounded")
                    Text("Mono").tag("mono")
                    Text("Cooper").tag("cooper")
                    Text("Zapfino").tag("zapfino")
                    Text("Blackmoor").tag("blackmoor")
                } label: { InfoLabel("Style", .clockStyle, icon: "textformat") }
                Picker(selection: $lockClockWeight) {
                    Text("Thin").tag("ultralight")
                    Text("Light").tag("light")
                    Text("Regular").tag("regular")
                    Text("Bold").tag("bold")
                } label: { InfoLabel("Weight", .clockWeight, icon: "bold") }
                .pickerStyle(.segmented)
                Slider(value: $lockClockScale, in: 0.6...1.4) {
                    InfoLabel("Size", .clockSize, icon: "textformat.size")
                } minimumValueLabel: { Text("A").font(.caption) } maximumValueLabel: { Text("A").font(.title3) }
            }
            .disabled(!lockScreenPlayer)
        }
        .formStyle(.grouped)
    }

    var spotifyTab: some View {
        Form {
            Section {
                if spotify.connected {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect") { spotify.disconnect() }
                    }
                } else {
                    TextField(text: $spotifyClientID) { InfoLabel("Client ID", .spotify, icon: "key") }
                    Button("Connect") { spotify.connect() }.disabled(spotifyClientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    Link("Get a Client ID", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                }
                if !spotify.status.isEmpty { Text(spotify.status).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}
