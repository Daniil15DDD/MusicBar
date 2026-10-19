import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showWaveform") private var showWaveform = true
    @AppStorage("showArtwork") private var showArtwork = true
    @AppStorage("preferredPlayer") private var preferredPlayer = "auto"
    @AppStorage("openPopoverOnClick") private var openPopoverOnClick = true
    @AppStorage("fallback") private var fallback = "icon"
    @AppStorage("reactiveAudio") private var reactiveAudio = false
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
                Toggle("Open player popover on click", isOn: $openPopoverOnClick)
                Text("When off, a click toggles play/pause. Right-click always opens the menu.").font(.caption).foregroundStyle(.secondary)
                Picker("Player", selection: $preferredPlayer) {
                    Text("Automatic").tag("auto")
                    Text("Apple Music").tag("music")
                    Text("Spotify").tag("spotify")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 470)
    }
}
