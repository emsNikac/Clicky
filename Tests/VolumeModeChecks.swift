import Foundation

enum VolumeModeChecks {
    static let speakerStages: [Float] = (1...16).map { speakerDecibels(scalar: Float($0) / 16) }

    // The built-in output's actual getter and reverse conversion use this curve.
    static func speakerDecibels(scalar: Float) -> Float { 63.5 * (sqrt(scalar) - 1) }

    static func speakerOutput(scalar: Float, muted: Bool = false) -> SystemOutputVolume {
        .init(deviceUID: "speakers", decibels: speakerDecibels(scalar: scalar), scalar: scalar,
              stageDecibels: speakerStages, isMuted: muted)
    }

    static func run() throws {
        try checkThresholds()
        try checkCurve()
        try checkLock()

        // Read only: never change the user's volume, play audio, or access a microphone.
        let current = SystemOutputMonitor.readSnapshot()
        if let stages = current.stageDecibels {
            try check(stages.count == 16 && stages.allSatisfy(\.isFinite), "Live stage curve is invalid.")
            print(String(format: "PASS: read the output's 16-stage hardware curve; stage 3 = %.3f dB.", stages[2]))
        } else {
            print("INFO: current output has no hardware stage curve; slider-ratio fallback applies when available.")
        }
    }

    private static func checkThresholds() throws {
        var policy = VolumeCompensation()
        // Every threshold, every normal system stage, and values between stages.
        for threshold in 1...16 {
            let cap = speakerStages[threshold - 1]
            for scalar in (1...400).map({ Float($0) / 400 }) + (1...16).map({ Float($0) / 16 }) {
                let output = speakerOutput(scalar: scalar)
                policy.update(mode: .constant, output: output, thresholdStage: threshold)
                let effective = output.decibels! + policy.gain
                try check(abs(effective - min(output.decibels!, cap)) < 0.0001 && policy.gain <= 0 &&
                          policy.status == .active,
                          "Threshold \(threshold) failed at Mac volume \(scalar * 100)%.")
                if scalar <= VolumeControls.scalar(for: threshold) {
                    try check(policy.gain == 0, "Constant boosted or attenuated below its threshold.")
                }
            }
        }
        policy.update(mode: .constant, output: speakerOutput(scalar: 1), thresholdStage: 3)
        let original = policy.gain
        policy.update(mode: .gradient, output: speakerOutput(scalar: 1), thresholdStage: 3)
        try check(policy.gain == 0, "Gradient applied the threshold.")
        policy.update(mode: .constant, output: speakerOutput(scalar: 1), thresholdStage: 3)
        try check(policy.gain == original, "Toggling modes captured a new target instead of using stage 3.")
        var relaunched = VolumeCompensation()
        relaunched.update(mode: .constant, output: speakerOutput(scalar: 1), thresholdStage: 3)
        try check(relaunched.gain == original, "Relaunch changed the threshold target.")

        let headphoneStages = (1...16).map { 20 * log10(Float($0) / 16) }
        let headphones = SystemOutputVolume(deviceUID: "headphones", decibels: 0, scalar: 1,
                                           stageDecibels: headphoneStages)
        policy.update(mode: .constant, output: headphones, thresholdStage: 3)
        try check(abs(policy.gain - headphoneStages[2]) < 0.0001, "Output change reused the speaker curve.")
        policy.update(mode: .constant, output: speakerOutput(scalar: 1), thresholdStage: 3)
        try check(policy.gain == original, "Returning to speakers lost their stage curve.")
        for scalar: Float in [0.0625, 0.1, 0.1875, 0.2, 0.5, 0.75, 1] {
            policy.update(mode: .constant, output: .init(deviceUID: "scalar-only", scalar: scalar), thresholdStage: 3)
            let effective = scalar * pow(10, policy.gain / 20)
            try check(abs(effective - min(scalar, 3.0 / 16)) < 0.000001 && policy.gain <= 0,
                      "Scalar-only output did not follow the threshold rule.")
        }
        for output in [speakerOutput(scalar: 0, muted: true), speakerOutput(scalar: 0),
                       speakerOutput(scalar: 0.5, muted: true)] {
            policy.update(mode: .constant, output: output, thresholdStage: 3)
            try check(policy.status == .muted && policy.gain == 0, "Muted output was compensated.")
        }
        for invalid: Float? in [nil, -1, 2, .nan, .infinity] {
            policy.update(mode: .constant, output: .init(deviceUID: "invalid", scalar: invalid), thresholdStage: 3)
            try check(policy.status == .unavailable && policy.gain == 0, "Invalid volume produced compensation.")
        }
        print("PASS: all 16 thresholds follow volume below the ceiling and hold above it, including fractional stages.")
        print("PASS: threshold survives mode/output changes and relaunch; mute and scalar-only fallback are correct.")
    }

    private static func checkCurve() throws {
        let curve = SystemOutputMonitor.stageCurve(minimum: -63.5, maximum: 0) {
            pow(($0 + 63.5) / 63.5, 2)
        }
        try check(curve?.count == 16, "Could not invert the built-in output's volume curve.")
        for (actual, expected) in zip(curve!, speakerStages) {
            try check(abs(actual - expected) < 0.0001,
                      "Stage curve used a linear dB or linear amplitude assumption.")
        }
        var policy = VolumeCompensation()
        for scalar: Float in [0.1, 3.0 / 16] {
            var output = speakerOutput(scalar: scalar)
            output.stageDecibels = curve
            policy.update(mode: .constant, output: output, thresholdStage: 3)
            try check(policy.gain == 0, "Native lookup rounding applied attenuation at or below stage 3.")
        }
        let linear = SystemOutputMonitor.stageCurve(minimum: -64, maximum: 0) { ($0 + 64) / 64 }
        try check(linear?.count == 16 && abs(linear![2] + 52) < 0.0001,
                  "Linear device curve was not inverted correctly.")
        try check(SystemOutputMonitor.stageCurve(minimum: -64, maximum: 0, decibelsToScalar: { _ in nil }) == nil,
                  "Missing native conversion produced a hardware curve.")
        try check(SystemOutputMonitor.stageCurve(minimum: -64, maximum: 0, decibelsToScalar: { _ in .nan }) == nil,
                  "Invalid conversion produced a hardware curve.")
        try check(SystemOutputMonitor.stageCurve(minimum: .nan, maximum: 0, decibelsToScalar: { _ in 1 }) == nil,
                  "Invalid native dB range was accepted.")
        try check(SystemOutputMonitor.stageCurve(minimum: -64, maximum: 0, decibelsToScalar: {
            $0 == -32 ? 0.99 : ($0 + 64) / 64
        }) == nil, "A nonmonotonic native conversion was accepted.")
        print("PASS: hardware stage lookup uses the inverse native curve, including the MacBook's nonlinear mapping.")
    }

    private static func checkLock() throws {
        var controls = VolumeControls(volume: 0.28)
        try check(controls.isLocked && controls.thresholdStage == 3, "New volume controls must start locked at stage 3.")
        try check(!controls.setThresholdStage(8) && !controls.setVolume(1) &&
                  controls.thresholdStage == 3 && controls.volume == 0.28,
                  "Locked controls accepted a programmatic volume or threshold change.")
        controls.isLocked = false
        try check(controls.setThresholdStage(5) && controls.setVolume(0.4), "Unlocking did not allow manual changes.")
        controls.isLocked = true
        try check(!controls.setThresholdStage(16) && !controls.setVolume(0) &&
                  controls.thresholdStage == 5 && controls.volume == 0.4,
                  "Relocking failed to preserve the selected values.")
        let restored = VolumeControls(volume: controls.volume, thresholdStage: controls.thresholdStage,
                                      isLocked: controls.isLocked)
        try check(restored == controls, "Restoring saved control values changed the lock or threshold.")
        controls.isLocked = false
        controls.setThresholdStage(.max)
        try check(controls.thresholdStage == 16, "Threshold exceeded the 16 system stages.")
        controls.setThresholdStage(.min)
        try check(controls.thresholdStage == 1, "Threshold fell below stage 1.")
        try check(!controls.setVolume(.nan), "Invalid manual volume was accepted.")
        print("PASS: lock blocks value changes, unlock allows editing, and saved values restore correctly.")
    }
}
