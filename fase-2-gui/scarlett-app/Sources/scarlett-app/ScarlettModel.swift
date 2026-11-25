import Foundation

// MARK: - State

struct RoutingState {
    var matrixMux: [Int] = Array(repeating: 0, count: 8)
    var outputMux: [Int] = Array(repeating: 0, count: 6)
    var captureMux: [Int] = Array(repeating: 0, count: 4)
}

struct ScarlettState {
    var clock: String = "?"
    var rate: Int = 0
    var sync: String = "?"
    var masterVolume: Float = 0
    var masterMute: Bool = false
    var masterSolo: Bool = false
    var masterPfl: Bool = false
    var dim: Bool = false
    var mono: Bool = false

    var inputs: [InputChannel] = (0..<8).map { InputChannel(index: $0) }
    var outputs: [OutputChannel] = (0..<6).map { OutputChannel(index: $0) }

    struct InputChannel {
        let index: Int
        var impedance: String = "Line"
        var pad: Bool = false
        var gain: String = "Lo"
        var mixLevel: Float = 0.75
        var pan: Float = 0.5
        var mute: Bool = false
        var solo: Bool = false
        var pfl: Bool = false
        var stereoLink: Bool = false
    }

    struct OutputChannel {
        let index: Int
        var volume: Float = 0
        var mute: Bool = false
        var solo: Bool = false
        var pfl: Bool = false
    }
}

// MARK: - View Model

@MainActor
final class ScarlettViewModel: ObservableObject {
    @Published var state = ScarlettState()
    @Published var isConnected = false
    @Published var meters: [UInt16] = []
    @Published var routing = RoutingState()
    @Published var activeMix: Int = 0
    @Published var routingPreset = "Custom"
    @Published var monitorSoloLeft = false
    @Published var monitorSoloRight = false
    @Published var presets: [ScarlettPreset] = ScarlettViewModel.loadPresets()
    @Published var lastError: String?
    @Published var flashSavedAt: Date?

    /// Held peak per meter channel, decays ~4 dB/s toward the live value.
    @Published var meterHold: [Float] = []

    private let client = ScarlettClient()
    private let daemon = DaemonManager.shared
    private var pollTimer: Timer?
    private var retryTask: Task<Void, Never>?
    private var pollFailures = 0
    private var preDimVolume: Float?

    /// Quick check: does the daemon accept connections right now?
    private func daemonAlive() async -> Bool {
        (try? await client.sendAsync("GET clock")) != nil
    }

    /// Make sure the daemon is running. Returns true if we spawned one
    /// (or one is already up), false if the binary couldn't be found.
    private func ensureDaemon() -> Bool {
        let ok = daemon.ensureRunning()
        if !ok {
            lastError = daemon.hasOwnedProcess
                ? "scarlett-daemon keeps crashing — check /tmp/scarlett-daemon.log"
                : "scarlett-daemon binary not found (SCARLETT_DAEMON?)"
        }
        return ok
    }

    private static let presetDefaultsKey = "scarlettPresets"

    private static func loadPresets() -> [ScarlettPreset] {
        guard let data = UserDefaults.standard.data(forKey: presetDefaultsKey),
              let stored = try? JSONDecoder().decode([ScarlettPreset].self, from: data)
        else { return [] }
        return stored
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetDefaultsKey)
        }
    }

    // MARK: - Connection

    func connect() async {
        guard !isConnected else { return }
        if !(await daemonAlive()) {
            ensureDaemon()
        }
        do {
            let resp = try await client.sendAsync("GET clock")
            guard resp.hasPrefix("OK") else {
                lastError = "daemon not responding"
                return
            }
            isConnected = true
            lastError = nil
            await refresh()
            await refreshRouting()
            if routing.outputMux.count >= 2 && routing.outputMux[0] != 18 {
                applyRoutingPreset("mix1")
            }
            syncAllChannelsToHardware()
            startPolling()
        } catch {
            lastError = "\(error)"
            fputs("connect error: \(error)\n", stderr)
        }
        if !isConnected { startAutoRetry() }
    }

    func disconnect() {
        stopPolling()
        retryTask?.cancel()
        retryTask = nil
        isConnected = false
        daemon.shutdown()
    }

    private func startAutoRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { @MainActor in
            while !isConnected {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if !(await daemonAlive()) {
                    let spawned = ensureDaemon()
                    if spawned {
                        lastError = "daemon starting…"
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
                do {
                    let resp = try await client.sendAsync("GET clock")
                    guard resp.hasPrefix("OK") else { continue }
                    isConnected = true
                    lastError = nil
                    await refresh()
                    await refreshRouting()
                    syncAllChannelsToHardware()
                    startPolling()
                    break
                } catch {
                    lastError = "\(error)"
                }
            }
            retryTask = nil
        }
    }

    // MARK: - Daemon helpers

    private func asyncDump() async throws -> [(String, String)] {
        let resp = try await client.sendAsync("DUMP")
        guard resp.hasPrefix("OK") else { throw ScarlettError.commandFailed(resp) }
        let parts = resp.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return parts.split(separator: " ").compactMap { token in
            let kv = token.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            return (String(kv[0]), String(kv[1]))
        }
    }

    private func asyncSet(_ key: String, _ value: String) async throws {
        let resp = try await client.sendAsync("SET \(key) \(value)")
        guard resp.hasPrefix("OK") else { throw ScarlettError.commandFailed(resp) }
    }

    private func asyncGetMeters() async throws -> [UInt16] {
        let resp = try await client.sendAsync("GET meters")
        guard resp.hasPrefix("OK ") else { throw ScarlettError.commandFailed(resp) }
        return String(resp.dropFirst(3)).split(separator: " ").compactMap { UInt16($0) }
    }

    // MARK: - Full refresh

    func refresh() async {
        guard isConnected else { return }
        do {
            let pairs = try await asyncDump()
            var s = state
            for (key, val) in pairs {
                switch key {
                case "clock":
                    if let n = Int(val), (0...2).contains(n) {
                        s.clock = ["Internal", "S/PDIF", "ADAT"][n]
                    } else {
                        s.clock = val
                    }
                case "rate": s.rate = Int(val) ?? 0
                case "sync": s.sync = val
                case "vol": s.masterVolume = Float(Int(val.replacingOccurrences(of: "dB", with: "")) ?? 0)
                case "mute": s.masterMute = val == "1"
                case let k where k.hasPrefix("imp"):
                    if let idx = Int(k.dropFirst(3)), idx >= 1, idx <= s.inputs.count {
                        s.inputs[idx-1].impedance = val
                    }
                case let k where k.hasPrefix("pad"):
                    if let idx = Int(k.dropFirst(3)), idx >= 1, idx <= s.inputs.count {
                        s.inputs[idx-1].pad = val == "On"
                    }
                case let k where k.hasPrefix("gain"):
                    if let idx = Int(k.dropFirst(4)), idx >= 1, idx <= s.inputs.count {
                        s.inputs[idx-1].gain = val
                    }
                default: break
                }
            }
            state = s
        } catch {
            fputs("refresh error: \(error)\n", stderr)
        }
    }

    // MARK: - Routing

    func refreshRouting() async {
        var r = RoutingState()
        for i in 0..<8 {
            if let v = try? await client.sendAsync("GET matrix:\(i)"),
               v.hasPrefix("OK src=") { r.matrixMux[i] = Int(v.dropFirst(7)) ?? 0 }
        }
        for i in 0..<6 {
            if let v = try? await client.sendAsync("GET output:\(i)"),
               v.hasPrefix("OK src=") { r.outputMux[i] = Int(v.dropFirst(7)) ?? 0 }
        }
        for i in 0..<4 {
            if let v = try? await client.sendAsync("GET capture:\(i)"),
               v.hasPrefix("OK src=") { r.captureMux[i] = Int(v.dropFirst(7)) ?? 0 }
        }
        routing = r
    }

    func setOutputMux(bus: Int, src: Int) {
        routing.outputMux[bus] = src
        Task { @MainActor in try? await asyncSet("output:\(bus)", "\(src)") }
    }

    func copyMixTo(_ target: Int) {
        guard isConnected else { return }
        let src = activeMix
        guard target != src else { return }
        Task { @MainActor in
            for i in routing.outputMux.indices where routing.outputMux[i] == src {
                _ = try? await asyncSet("output:\(i)", "\(target)")
            }
            for i in routing.matrixMux.indices where routing.matrixMux[i] == src {
                _ = try? await asyncSet("matrix:\(i)", "\(target)")
            }
            await refreshRouting()
        }
    }

    // MARK: - Monitoring Mode & Routing presets

    var monitoringMode: String {
        guard routing.outputMux.count >= 2 else { return "custom" }
        let out0 = routing.outputMux[0]
        let out1 = routing.outputMux[1]
        if out0 == 0 && out1 == 1 { return "daw" }
        if out0 == 12 && out1 == 12 { return "direct" }
        if out0 == 18 && out1 == 19 { return "mix" }
        return "custom"
    }

    func setMonitoringMode(_ mode: String) {
        switch mode {
        case "daw": applyRoutingPreset("daw")
        case "direct": applyRoutingPreset("direct")
        case "mix": applyRoutingPreset("mix1")
        default: break
        }
    }

    func applyRoutingPreset(_ preset: String) {
        guard isConnected else { return }
        Task { @MainActor in
            // Feedback Protection: Always lock capture to physical hardware inputs (12..17)
            for i in 0..<4 { _ = try? await asyncSet("capture:\(i)", "\(12 + i)") }
            _ = try? await asyncSet("capture:4", "16")
            _ = try? await asyncSet("capture:5", "17")

            switch preset {
            case "daw":
                // Route outputs 0-3 (Mon L/R, HP 1 L/R, HP 2 L/R) to DAW 1-2 (PCM 1 & 2)
                for bus in [0, 2] { _ = try? await asyncSet("output:\(bus)", "0") }
                for bus in [1, 3] { _ = try? await asyncSet("output:\(bus)", "1") }
                _ = try? await asyncSet("output:4", "16")
                _ = try? await asyncSet("output:5", "17")
                routingPreset = "DAW / GarageBand"

            case "direct":
                // Direct Analog 1 (Guitar) to outputs 0-3 in both ears (zero latency)
                for bus in 0..<4 { _ = try? await asyncSet("output:\(bus)", "12") }
                _ = try? await asyncSet("output:4", "16")
                _ = try? await asyncSet("output:5", "17")
                routingPreset = "Direct Guitar"

            case "mix1":
                // Route outputs 0-3 to Mix 1 (DSP: Mix 1 L = 18, Mix 1 R = 19)
                for bus in [0, 2] { _ = try? await asyncSet("output:\(bus)", "18") }
                for bus in [1, 3] { _ = try? await asyncSet("output:\(bus)", "19") }
                _ = try? await asyncSet("output:4", "16")
                _ = try? await asyncSet("output:5", "17")
                // Setup matrix inputs: 0..3=Analog 1..4 (12..15), 4..5=SPDIF (16..17), 6..7=PCM 1..2 (0..1)
                let mux = [12, 13, 14, 15, 16, 17, 0, 1]
                for (idx, src) in mux.enumerated() { _ = try? await asyncSet("matrix:\(idx)", "\(src)") }
                // Set safe moderate gains for Guitar and DAW in Mix 1 (-14 dB)
                _ = try? await asyncSet("matrix:0.0", "-14")
                _ = try? await asyncSet("matrix:1.0", "-14")
                _ = try? await asyncSet("matrix:0.6", "-14")
                _ = try? await asyncSet("matrix:1.7", "-14")
                routingPreset = "Mix 1 (DSP)"

            case "default":
                for bus in [0, 2] { _ = try? await asyncSet("output:\(bus)", "0") }
                for bus in [1, 3] { _ = try? await asyncSet("output:\(bus)", "1") }
                _ = try? await asyncSet("output:4", "16")
                _ = try? await asyncSet("output:5", "17")
                let mux = [12, 13, 14, 15, 16, 17, 0, 1]
                for (idx, src) in mux.enumerated() { _ = try? await asyncSet("matrix:\(idx)", "\(src)") }
                routingPreset = "Default"

            default:
                break
            }
            await refreshRouting()
        }
    }

    // MARK: - Master controls

    private func applyMasterVolume(_ dB: Int) {
        let clamped = max(-128, min(0, dB))
        var s = state; s.masterVolume = Float(clamped); state = s
        Task { @MainActor in
            do { try await asyncSet("volume", "\(clamped)") }
            catch { fputs("setVolume error: \(error)\n", stderr) }
        }
    }

    func setVolume(_ dB: Int) {
        guard isConnected else { return }
        if state.dim || preDimVolume != nil {
            var s = state; s.dim = false; state = s
            preDimVolume = nil
        }
        applyMasterVolume(dB)
    }

    func setMute(_ on: Bool) {
        guard isConnected else { return }
        var s = state; s.masterMute = on; state = s
        Task { @MainActor in
            do {
                try await asyncSet("mute", on ? "on" : "off")
                if !on && monitorSoloLeft != monitorSoloRight {
                    syncMonitorChannelMutes()
                }
            }
            catch { fputs("setMute error: \(error)\n", stderr) }
        }
    }

    // MARK: - Preamp controls

    func setGain(ch: Int, _ mode: String) {
        guard isConnected, ch >= 1, ch <= state.inputs.count else { return }
        let isHi = mode == "hi"
        var s = state
        s.inputs[ch-1].gain = isHi ? "Hi" : "Lo"
        if ch <= 2 {
            s.inputs[ch-1].impedance = isHi ? "Hi-Z" : "Line"
        }
        state = s
        let key = ch <= 2 ? "impedance:\(ch)" : "gain:\(ch)"
        let value = ch <= 2 ? (isHi ? "hi-z" : "line") : mode
        Task { @MainActor in
            do { try await asyncSet(key, value) }
            catch { fputs("setGain error: \(error)\n", stderr) }
        }
    }

    func setPad(ch: Int, _ on: Bool) {
        guard isConnected else { return }
        if ch >= 1, ch <= state.inputs.count {
            var s = state; s.inputs[ch-1].pad = on; state = s
        }
        Task { @MainActor in
            do { try await asyncSet("pad:\(ch)", on ? "on" : "off") }
            catch { fputs("setPad error: \(error)\n", stderr) }
        }
    }

    // MARK: - Monitor controls

    func toggleDim() {
        guard isConnected else { return }
        if !state.dim {
            preDimVolume = state.masterVolume
            var s = state; s.dim = true; state = s
            let dimmed = max(-128, Int(state.masterVolume.rounded()) - 20)
            applyMasterVolume(dimmed)
        } else {
            var s = state; s.dim = false; state = s
            let restored = Int((preDimVolume ?? 0).rounded())
            preDimVolume = nil
            applyMasterVolume(restored)
        }
    }

    func toggleMonitorSoloLeft() {
        monitorSoloLeft.toggle()
        syncMonitorChannelMutes()
    }

    func toggleMonitorSoloRight() {
        monitorSoloRight.toggle()
        syncMonitorChannelMutes()
    }

    private func syncMonitorChannelMutes() {
        guard isConnected, !state.masterMute else { return }
        let muteLeft = monitorSoloRight && !monitorSoloLeft
        let muteRight = monitorSoloLeft && !monitorSoloRight
        Task { @MainActor in
            do {
                try await asyncSet("mute:1", muteLeft ? "on" : "off")
                try await asyncSet("mute:2", muteRight ? "on" : "off")
            } catch {
                fputs("syncMonitorChannelMutes error: \(error)\n", stderr)
            }
        }
    }

    func toggleMono() {
        guard isConnected else { return }
        var s = state; s.mono.toggle(); state = s
        Task { @MainActor in
            do { try await asyncSet("mono", s.mono ? "on" : "off") }
            catch { fputs("toggleMono error: \(error)\n", stderr) }
        }
    }

    // MARK: - Clock & sample rate

    func setClockSource(_ source: String) {
        guard isConnected else { return }
        let value: String
        switch source {
        case "S/PDIF": value = "spdif"
        case "ADAT": value = "adat"
        default: value = "internal"
        }
        Task { @MainActor in
            do {
                try await asyncSet("clock", value)
                await refresh()
            } catch { fputs("setClock error: \(error)\n", stderr) }
        }
    }

    func setSampleRate(_ rate: Int) {
        guard isConnected else { return }
        Task { @MainActor in
            do {
                try await asyncSet("rate", "\(rate)")
                await refresh()
            } catch { fputs("setRate error: \(error)\n", stderr) }
        }
    }

    // MARK: - Meter holds

    func resetMeterHold(_ index: Int) {
        guard meterHold.indices.contains(index) else { return }
        meterHold[index] = 0
    }

    // MARK: - Channel controls (Faders, Mute, Pan)

    func toggleInputMute(_ ch: Int) {
        guard state.inputs.indices.contains(ch) else { return }
        var s = state
        s.inputs[ch].mute.toggle()
        let newMute = s.inputs[ch].mute
        let peer = ch % 2 == 0 ? ch + 1 : ch - 1
        if s.inputs[ch].stereoLink && s.inputs.indices.contains(peer) {
            s.inputs[peer].mute = newMute
        }
        state = s
        updateHardwareMatrixGain(ch: ch)
        if s.inputs[ch].stereoLink && s.inputs.indices.contains(peer) {
            updateHardwareMatrixGain(ch: peer)
        }
    }

    func toggleInputSolo(_ ch: Int) {
        guard state.inputs.indices.contains(ch) else { return }
        var s = state; s.inputs[ch].solo.toggle(); state = s
        syncAllChannelsToHardware()
    }

    func toggleInputPfl(_ ch: Int) {
        guard state.inputs.indices.contains(ch) else { return }
        var s = state; s.inputs[ch].pfl.toggle(); state = s
    }

    func toggleInputStereoLink(_ ch: Int) {
        guard state.inputs.indices.contains(ch) else { return }
        var s = state
        s.inputs[ch].stereoLink.toggle()
        let isLinked = s.inputs[ch].stereoLink
        let peer = ch % 2 == 0 ? ch + 1 : ch - 1
        if s.inputs.indices.contains(peer) {
            s.inputs[peer].stereoLink = isLinked
            if isLinked {
                s.inputs[peer].mixLevel = s.inputs[ch].mixLevel
                s.inputs[peer].mute = s.inputs[ch].mute
            }
        }
        state = s
        updateHardwareMatrixGain(ch: ch)
        if s.inputs.indices.contains(peer) {
            updateHardwareMatrixGain(ch: peer)
        }
    }

    func setInputPan(ch: Int, _ value: Float) {
        guard state.inputs.indices.contains(ch) else { return }
        var s = state; s.inputs[ch].pan = min(1, max(0, value)); state = s
        updateHardwareMatrixGain(ch: ch)
    }

    // MARK: - Mix levels (per-channel faders)

    func setMixLevel(ch: Int, _ level: Float) {
        guard state.inputs.indices.contains(ch) else { return }
        let clamped = min(1, max(0, level))
        var s = state
        s.inputs[ch].mixLevel = clamped
        let peer = ch % 2 == 0 ? ch + 1 : ch - 1
        if s.inputs[ch].stereoLink && s.inputs.indices.contains(peer) {
            s.inputs[peer].mixLevel = clamped
        }
        state = s
        updateHardwareMatrixGain(ch: ch)
        if s.inputs[ch].stereoLink && s.inputs.indices.contains(peer) {
            updateHardwareMatrixGain(ch: peer)
        }
    }

    // MARK: - Stereo Channel Helpers

    func setStereoMixLevel(left: Int, right: Int, _ level: Float) {
        guard state.inputs.indices.contains(left), state.inputs.indices.contains(right) else { return }
        let clamped = min(1, max(0, level))
        var s = state
        s.inputs[left].mixLevel = clamped
        s.inputs[right].mixLevel = clamped
        state = s
        updateHardwareMatrixGain(ch: left)
        updateHardwareMatrixGain(ch: right)
    }

    func setStereoPan(left: Int, right: Int, _ balance: Float) {
        guard state.inputs.indices.contains(left), state.inputs.indices.contains(right) else { return }
        let clamped = min(1, max(0, balance))
        var s = state
        s.inputs[left].pan = clamped
        s.inputs[right].pan = clamped
        state = s
        updateHardwareMatrixGain(ch: left)
        updateHardwareMatrixGain(ch: right)
    }

    func toggleStereoMute(left: Int, right: Int) {
        guard state.inputs.indices.contains(left), state.inputs.indices.contains(right) else { return }
        var s = state
        let newMute = !s.inputs[left].mute
        s.inputs[left].mute = newMute
        s.inputs[right].mute = newMute
        state = s
        updateHardwareMatrixGain(ch: left)
        updateHardwareMatrixGain(ch: right)
    }

    func toggleStereoSolo(left: Int, right: Int) {
        guard state.inputs.indices.contains(left), state.inputs.indices.contains(right) else { return }
        var s = state
        let newSolo = !s.inputs[left].solo
        s.inputs[left].solo = newSolo
        s.inputs[right].solo = newSolo
        state = s
        syncAllChannelsToHardware()
    }

    func toggleStereoPfl(left: Int, right: Int) {
        guard state.inputs.indices.contains(left), state.inputs.indices.contains(right) else { return }
        var s = state
        let newPfl = !s.inputs[left].pfl
        s.inputs[left].pfl = newPfl
        s.inputs[right].pfl = newPfl
        state = s
    }

    func syncAllChannelsToHardware() {
        for ch in state.inputs.indices {
            updateHardwareMatrixGain(ch: ch)
        }
    }

    private func updateHardwareMatrixGain(ch: Int) {
        guard state.inputs.indices.contains(ch) else { return }
        let input = state.inputs[ch]
        let mixIdx = activeMix
        let leftMix = mixIdx * 2
        let rightMix = mixIdx * 2 + 1

        let anySolo = state.inputs.contains { $0.solo }
        let isMuted = input.mute || (anySolo && !input.solo)
        let dB: Int
        if isMuted {
            dB = -128
        } else {
            dB = Int(Self.mixDB(for: input.mixLevel).rounded())
        }

        Task { @MainActor in
            if ch == 4 || ch == 6 {
                // Stereo Left channel (S/PDIF L or DAW 1) -> routes only to Left mix
                let pan = input.pan
                let leftGain = isMuted ? -128 : ((pan > 0.5) ? max(-128, dB - Int(round((pan - 0.5) * 2 * 30))) : dB)
                _ = try? await asyncSet("matrix:\(leftMix).\(ch)", "\(leftGain)")
                _ = try? await asyncSet("matrix:\(rightMix).\(ch)", "-128")
            } else if ch == 5 || ch == 7 {
                // Stereo Right channel (S/PDIF R or DAW 2) -> routes only to Right mix
                let pan = input.pan
                let rightGain = isMuted ? -128 : ((pan < 0.5) ? max(-128, dB - Int(round((0.5 - pan) * 2 * 30))) : dB)
                _ = try? await asyncSet("matrix:\(leftMix).\(ch)", "-128")
                _ = try? await asyncSet("matrix:\(rightMix).\(ch)", "\(rightGain)")
            } else {
                // Mono analog channels (Inputs 1-4) -> pan to Left & Right
                let pan = input.pan
                let leftGain = isMuted ? -128 : (pan <= 0.5 ? dB : max(-128, dB - Int(round((pan - 0.5) * 2 * 30))))
                let rightGain = isMuted ? -128 : (pan >= 0.5 ? dB : max(-128, dB - Int(round((0.5 - pan) * 2 * 30))))
                _ = try? await asyncSet("matrix:\(leftMix).\(ch)", "\(leftGain)")
                _ = try? await asyncSet("matrix:\(rightMix).\(ch)", "\(rightGain)")
            }
        }
    }

    // MARK: - dB conversion

    static func mixDB(for position: Float) -> Float {
        if position <= 0.75 { return -128 + (position / 0.75) * 116 } // 0.75 fader = safe -12 dB headroom
        return -12 + ((position - 0.75) / 0.25) * 12 // up to 0 dB max at top
    }

    static func dBString(from position: Float) -> String {
        let dB = Int(mixDB(for: position).rounded())
        if dB <= -128 { return "-∞" }
        return "\(dB >= 0 ? "+" : "")\(dB)"
    }

    static func volumeDBString(_ volume: Float) -> String {
        let dB = Int(volume.rounded())
        return dB <= -128 ? "-∞" : "\(dB >= 0 ? "+" : "")\(dB)"
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.pollMeters() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollMeters() async {
        guard isConnected else { return }
        do {
            let m = try await asyncGetMeters()
            meters = m
            pollFailures = 0
            updateMeterHold(m)
        } catch {
            pollFailures += 1
            if pollFailures >= 25 {
                lastError = "daemon lost"
                stopPolling()
                isConnected = false
                startAutoRetry()
            }
        }
    }

    // MARK: - Held peaks

    private func updateMeterHold(_ m: [UInt16]) {
        if meterHold.count != m.count {
            meterHold = m.map { Float($0) }
            return
        }
        /// Decay ~4 dB/s on a 96 dB span over the 0.1 s poll interval.
        let decay = Float(65535) * (4.0 / 96.0) * 0.1
        for i in m.indices {
            let cur = Float(m[i])
            meterHold[i] = max(meterHold[i] - decay, cur)
        }
    }

    func meterHoldLevel(_ index: Int) -> CGFloat {
        guard meterHold.indices.contains(index) else { return 0 }
        return CGFloat(meterHold[index]) / 65535.0
    }

    // MARK: - Presets

    func capturePreset(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var gains = [Int](repeating: -128, count: 64)
        if await daemonAlive() {
            for node in 0..<64 {
                guard let v = try? await client.sendAsync("GET matrix:\(node / 8).\(node % 8)"),
                      v.hasPrefix("OK ") else { continue }
                if let dB = Int(v.dropFirst(3).split(separator: " ").first ?? "") {
                    gains[node] = dB
                }
            }
        }
        let preset = ScarlettPreset(
            id: UUID(),
            name: trimmed,
            createdAt: Date(),
            volume: state.masterVolume,
            mute: state.masterMute,
            matrixMux: routing.matrixMux,
            outputMux: routing.outputMux,
            captureMux: routing.captureMux,
            gainModes: state.inputs.enumerated().map { i, ch in
                i < 2 ? ch.impedance : (ch.gain == "Hi" ? "Hi" : "Lo")
            },
            pads: state.inputs.map { $0.pad },
            mixLevels: state.inputs.map { $0.mixLevel },
            pans: state.inputs.map { $0.pan },
            mutes: state.inputs.map { $0.mute },
            solos: state.inputs.map { $0.solo },
            pfls: state.inputs.map { $0.pfl },
            stereoLinks: state.inputs.map { $0.stereoLink },
            matrixGains: gains,
            activeMix: activeMix
        )
        if let idx = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        persistPresets()
    }

    func loadPreset(_ preset: ScarlettPreset) {
        guard isConnected else { return }
        Task { @MainActor in
            for i in preset.matrixMux.indices {
                _ = try? await asyncSet("matrix:\(i)", "\(preset.matrixMux[i])")
            }
            for i in preset.outputMux.indices {
                _ = try? await asyncSet("output:\(i)", "\(preset.outputMux[i])")
            }
            for i in preset.captureMux.indices {
                _ = try? await asyncSet("capture:\(i)", "\(preset.captureMux[i])")
            }
            for node in 0..<min(preset.matrixGains.count, 64) {
                _ = try? await asyncSet("matrix:\(node / 8).\(node % 8)", "\(preset.matrixGains[node])")
            }
            for ch in 0..<preset.gainModes.count {
                let chNo = ch + 1
                let hi = preset.gainModes[ch] == "Hi" || preset.gainModes[ch] == "Hi-Z"
                if chNo <= 2 {
                    _ = try? await asyncSet("impedance:\(chNo)", hi ? "hi-z" : "line")
                } else {
                    _ = try? await asyncSet("gain:\(chNo)", hi ? "hi" : "lo")
                }
                _ = try? await asyncSet("pad:\(chNo)", preset.pads[ch] ? "on" : "off")
            }
            _ = try? await asyncSet("volume", "\(Int(preset.volume))")
            _ = try? await asyncSet("mute", preset.mute ? "on" : "off")

            var s = state
            if preset.gainModes.count == s.inputs.count {
                for (i, mode) in preset.gainModes.enumerated() {
                    if i < 2 { s.inputs[i].impedance = (mode == "Hi-Z") ? "Hi-Z" : "Line" }
                    s.inputs[i].gain = mode == "Hi" ? "Hi" : "Lo"
                }
            }
            if preset.pads.count == s.inputs.count {
                for i in preset.pads.indices { s.inputs[i].pad = preset.pads[i] }
            }
            if preset.mixLevels.count == s.inputs.count {
                for i in preset.mixLevels.indices { s.inputs[i].mixLevel = preset.mixLevels[i] }
            }
            if preset.pans.count == s.inputs.count {
                for i in preset.pans.indices { s.inputs[i].pan = preset.pans[i] }
            }
            if preset.mutes.count == s.inputs.count {
                for i in preset.mutes.indices { s.inputs[i].mute = preset.mutes[i] }
            }
            if preset.solos.count == s.inputs.count {
                for i in preset.solos.indices { s.inputs[i].solo = preset.solos[i] }
            }
            if preset.pfls.count == s.inputs.count {
                for i in preset.pfls.indices { s.inputs[i].pfl = preset.pfls[i] }
            }
            if preset.stereoLinks.count == s.inputs.count {
                for i in preset.stereoLinks.indices { s.inputs[i].stereoLink = preset.stereoLinks[i] }
            }
            s.masterVolume = preset.volume
            s.masterMute = preset.mute
            if preset.activeMix >= 0 && preset.activeMix < 8 {
                activeMix = preset.activeMix
            }
            state = s
            routing = RoutingState(
                matrixMux: preset.matrixMux.count == 8 ? preset.matrixMux : routing.matrixMux,
                outputMux: preset.outputMux.count == 6 ? preset.outputMux : routing.outputMux,
                captureMux: preset.captureMux.count == 4 ? preset.captureMux : routing.captureMux
            )
        }
    }

    func deletePreset(_ preset: ScarlettPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    func exportPreset(_ preset: ScarlettPreset, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preset).write(to: url)
    }

    func importPreset(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let preset = try? JSONDecoder().decode(ScarlettPreset.self, from: data)
        else { return }
        if let idx = presets.firstIndex(where: { $0.name == preset.name }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        persistPresets()
        loadPreset(preset)
    }

    // MARK: - Flash persistence

    func saveToHardware() async -> Bool {
        do {
            let resp = try await client.saveToHardwareAsync()
            guard resp.hasPrefix("OK") else { return false }
            flashSavedAt = Date()
            return true
        } catch {
            return false
        }
    }
}
