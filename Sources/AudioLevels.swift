import Foundation
import CoreAudio
import AudioToolbox

/// Five frequency-band levels (bass → treble) from a system-audio tap, so the waveform follows the music.
/// Runs only while a track is playing. Cost: five one-pole filters per sample plus a 20 Hz UI timer.
final class AudioLevels: ObservableObject {
    @Published private(set) var levels = [Float](repeating: 0, count: 5)
    /// False when the tap could not start or only silence arrived (e.g. permission denied) → caller falls back.
    @Published private(set) var live = true
    /// True only while the tap is actually running (opt-in setting + playing).
    @Published private(set) var running = false

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agg = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var timer: Timer?
    private let ioQueue = DispatchQueue(label: "musicbar.audio", qos: .utility)
    private let lock = NSLock()
    private var raw = [Float](repeating: 0, count: 5)      // guarded by lock
    private var lp = [Float](repeating: 0, count: 4)       // ioQueue only
    private var peak = [Float](repeating: 0.002, count: 5) // main only
    private var ticks = 0
    private var sawSignal = false

    // One-pole low-pass coefficients for 150 / 500 / 1500 / 4000 Hz at 48 kHz.
    private let coef: [Float] = [150, 500, 1500, 4000].map { 1 - exp(-2 * .pi * $0 / 48000) }

    func start() {
        guard tap == AudioObjectID(kAudioObjectUnknown) else { return }
        ticks = 0; sawSignal = false; live = true
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr, let outUID = defaultOutputUID() else { return fail() }

        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ORBTTap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg) == noErr,
              AudioDeviceCreateIOProcIDWithBlock(&proc, agg, ioQueue, { [weak self] _, inData, _, _, _ in
                  self?.process(inData)
              }) == noErr,
              AudioDeviceStart(agg, proc) == noErr else { return fail() }

        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let proc, agg != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(agg, proc)
            AudioDeviceDestroyIOProcID(agg, proc)
        }
        proc = nil
        if agg != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyAggregateDevice(agg); agg = AudioObjectID(kAudioObjectUnknown) }
        if tap != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tap); tap = AudioObjectID(kAudioObjectUnknown) }
        levels = [Float](repeating: 0, count: 5)
        running = false
    }

    private func fail() { stop(); live = false }

    private func defaultOutputUID() -> String? {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        addr.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    // Audio thread: split into bands with cascaded low-passes, keep per-band RMS.
    private func process(_ inData: UnsafePointer<AudioBufferList>?) {
        guard let inData else { return }
        var sums = [Float](repeating: 0, count: 5)
        var n = 0
        for buf in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)) {
            guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let ch = max(Int(buf.mNumberChannels), 1)
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            var i = 0
            while i + ch <= count {
                let x = ch > 1 ? (p[i] + p[i + 1]) * 0.5 : p[i]
                for k in 0..<4 { lp[k] += coef[k] * (x - lp[k]) }
                let b0 = lp[0], b1 = lp[1] - lp[0], b2 = lp[2] - lp[1], b3 = lp[3] - lp[2], b4 = x - lp[3]
                sums[0] += b0 * b0; sums[1] += b1 * b1; sums[2] += b2 * b2; sums[3] += b3 * b3; sums[4] += b4 * b4
                n += 1
                i += ch
            }
        }
        guard n > 0 else { return }
        lock.lock()
        for k in 0..<5 { raw[k] = (sums[k] / Float(n)).squareRoot() }
        lock.unlock()
    }

    // Main thread, 20 Hz: normalise against a slowly decaying per-band peak, so loud beats stand out
    // and flat passages stay low. Fast attack, slower release.
    private func tick() {
        lock.lock(); let r = raw; lock.unlock()
        ticks += 1
        if r.contains(where: { $0 > 1e-5 }) { sawSignal = true }
        if ticks == 80, !sawSignal { live = false }
        var out = levels
        for k in 0..<5 {
            peak[k] = max(r[k], peak[k] * 0.995, 0.002)
            let v = pow(r[k] / peak[k], 1.5)
            out[k] += (v - out[k]) * (v > out[k] ? 0.6 : 0.2)
        }
        levels = out
    }
}
