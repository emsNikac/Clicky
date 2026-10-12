import Foundation

enum VolumeMode: String, CaseIterable, Identifiable, Sendable {
    case gradient, constant
    var id: String { rawValue }
    var title: String { self == .gradient ? "Gradient" : "Constant" }
}

struct SystemOutputVolume: Equatable, Sendable {
    var deviceUID: String?
    var decibels: Float?
    var isMuted = false
}

enum ConstantVolumeStatus: Equatable, Sendable {
    case active, muted, limited, unavailable

    var message: String {
        switch self {
        case .active: "Keeps the current loudness as Mac volume changes. System mute still applies."
        case .muted: "System output is muted. Unmute to hear Clicky."
        case .limited: "Mac volume is too low to hold this loudness without distortion."
        case .unavailable: "This output doesn't expose its volume. Clicky follows the output volume."
        }
    }
}

/// Compensation uses the hardware's dB value, not its nonlinear slider position.
struct VolumeCompensation {
    static let maximumBoost: Float = 12
    private(set) var references: [String: Float]
    private(set) var gain: Float = 0
    private(set) var status: ConstantVolumeStatus = .unavailable

    init(references: [String: Float] = [:]) {
        self.references = references.filter { $0.value.isFinite && (-160...24).contains($0.value) }
    }

    mutating func update(mode: VolumeMode, output: SystemOutputVolume, resetReference: Bool = false) {
        gain = 0
        guard mode == .constant else { status = .active; return }
        if output.isMuted { status = .muted; return }
        guard let uid = output.deviceUID, let current = output.decibels,
              current.isFinite, (-160...24).contains(current) else {
            status = .unavailable
            return
        }
        if resetReference || references[uid] == nil { references[uid] = current }
        let desired = references[uid]! - current
        gain = max(-96, min(Self.maximumBoost, desired))
        status = desired > Self.maximumBoost ? .limited : .active
    }
}
