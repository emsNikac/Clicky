import Foundation

enum VolumeMode: String, CaseIterable, Identifiable, Sendable {
    case gradient, constant
    var id: String { rawValue }
    var title: String { self == .gradient ? "Gradient" : "Constant" }
}

struct SystemOutputVolume: Equatable, Sendable {
    var deviceUID: String?
    var decibels: Float?
    var scalar: Float?
    var stageDecibels: [Float]?
    var isMuted = false
}

struct VolumeControls: Equatable, Sendable {
    static let stageCount = 16
    static let stageRange = 1...stageCount
    static let defaultThreshold = 3
    private(set) var volume: Float
    private(set) var thresholdStage: Int
    var isLocked: Bool

    init(volume: Float = 0.6, thresholdStage: Int = defaultThreshold, isLocked: Bool = true) {
        self.volume = volume.isFinite ? max(0, min(1, volume)) : 0.6
        self.thresholdStage = Self.clampStage(thresholdStage)
        self.isLocked = isLocked
    }

    static func clampStage(_ stage: Int) -> Int { max(stageRange.lowerBound, min(stageCount, stage)) }
    static func scalar(for stage: Int) -> Float { Float(clampStage(stage)) / Float(stageCount) }

    @discardableResult
    mutating func setVolume(_ value: Float) -> Bool {
        guard !isLocked, value.isFinite else { return false }
        let value = max(0, min(1, value))
        guard value != volume else { return false }
        volume = value
        return true
    }

    @discardableResult
    mutating func setThresholdStage(_ stage: Int) -> Bool {
        guard !isLocked else { return false }
        let stage = Self.clampStage(stage)
        guard stage != thresholdStage else { return false }
        thresholdStage = stage
        return true
    }
}

enum ConstantVolumeStatus: Equatable, Sendable {
    case active, muted, unavailable

    var message: String {
        switch self {
        case .active: "Follows Mac volume up to the threshold, then holds that level."
        case .muted: "System output is muted. Unmute to hear Clicky."
        case .unavailable: "This output doesn't expose its volume. The threshold is unavailable."
        }
    }
}

/// Constant is a ceiling at an explicit Mac volume stage, never a boost or a captured reference.
struct VolumeCompensation {
    private(set) var gain: Float = 0
    private(set) var status: ConstantVolumeStatus = .unavailable

    mutating func update(mode: VolumeMode, output: SystemOutputVolume, thresholdStage: Int) {
        gain = 0
        guard mode == .constant else { status = .active; return }
        if output.isMuted || output.scalar == 0 { status = .muted; return }
        let stage = VolumeControls.clampStage(thresholdStage)
        if let scalar = output.scalar, scalar.isFinite, scalar > 0,
           scalar <= VolumeControls.scalar(for: stage) {
            // Follow the system exactly below the selected stage, including at
            // the boundary where a computed dB lookup can have rounding error.
            status = .active
            return
        }
        if let current = output.decibels, current.isFinite, (-160...24).contains(current),
           let stages = output.stageDecibels, stages.count == VolumeControls.stageCount,
           stages.allSatisfy({ $0.isFinite && (-160...24).contains($0) }),
           zip(stages, stages.dropFirst()).allSatisfy({ $0 <= $1 }) {
            gain = min(0, stages[stage - 1] - current)
            status = .active
            return
        }
        // Scalar-only outputs have no device gain curve; use the volume ratio.
        guard let scalar = output.scalar, scalar.isFinite, scalar > 0, scalar <= 1 else {
            status = .unavailable
            return
        }
        gain = 20 * log10(min(1, VolumeControls.scalar(for: stage) / scalar))
        status = .active
    }
}
