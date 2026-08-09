import Foundation

/// Complete snapshot of every user-controllable value. Stored in UserDefaults
/// (in-app preset list) and as `.6i6` JSON files via Export/Import.
struct ScarlettPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date

    /// Master volume in dB and mute state.
    var volume: Float
    var mute: Bool

    /// Wiring: matrix mux (8 entries), output mux (6), capture mux (4).
    var matrixMux: [Int]
    var outputMux: [Int]
    var captureMux: [Int]

    /// Per-input preamp mode (ch 1-2: "Line"|"Hi-Z", ch 3-4: "Lo"|"Hi").
    var gainModes: [String]
    var pads: [Bool]

    /// Active-mix faders and per-channel state.
    var mixLevels: [Float]
    var pans: [Float]
    var mutes: [Bool]
    var solos: [Bool]
    var pfls: [Bool]
    var stereoLinks: [Bool]

    /// Full matrix gain table, 64 entries: node = mix * 8 + channel, in dB.
    var matrixGains: [Int]

    /// Mix that was in view when the snapshot was taken.
    var activeMix: Int
}