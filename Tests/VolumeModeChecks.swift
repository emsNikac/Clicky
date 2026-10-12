import Foundation

enum VolumeModeChecks {
    static func run() throws {
        var policy = VolumeCompensation()
        let initial = SystemOutputVolume(deviceUID: "speakers", decibels: -30)
        policy.update(mode: .constant, output: initial)
        let baseline = amplitude(decibels: -30)
        for volume: Float in [-18, -12, -24, -36, -30] {
            policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: volume))
            let audible = amplitude(decibels: volume + policy.gain)
            try check(abs(audible - baseline) < 0.000001,
                      "Constant mode changed loudness when system volume became \(volume) dB.")
        }
        policy.update(mode: .gradient, output: .init(deviceUID: "speakers", decibels: -12))
        try check(policy.gain == 0, "Gradient mode still applies constant compensation.")
        policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -12), resetReference: true)
        try check(policy.gain == 0 && policy.references["speakers"] == -12,
                  "Re-enabling Constant failed to capture the current loudness.")

        policy.update(mode: .constant, output: .init(deviceUID: "headphones", decibels: -25))
        try check(policy.gain == 0, "A new output inherited another output's compensation.")
        policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -6))
        try check(policy.gain == -6, "Returning to speakers lost their reference level.")
        var relaunched = VolumeCompensation(references: policy.references)
        relaunched.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -3))
        try check(relaunched.gain == -9, "Restoring persisted references changed target loudness.")

        let savedReferences = policy.references
        policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -160, isMuted: true))
        try check(policy.gain == 0 && policy.status == .muted && policy.references == savedReferences,
                  "Muted output was boosted or replaced its reference.")
        policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -6))
        try check(policy.gain == -6, "Unmuting failed to restore compensation.")
        policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -90))
        try check(policy.gain == VolumeCompensation.maximumBoost && policy.status == .limited,
                  "Very low output volume caused unbounded gain.")
        for invalid: Float? in [nil, .nan, .infinity, -.infinity] {
            policy.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: invalid))
            try check(policy.gain == 0 && policy.status == .unavailable,
                      "Unavailable hardware volume produced compensation.")
        }
        var initiallyMuted = VolumeCompensation()
        initiallyMuted.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -160, isMuted: true))
        initiallyMuted.update(mode: .constant, output: .init(deviceUID: "speakers", decibels: -20))
        try check(initiallyMuted.gain == 0 && initiallyMuted.references["speakers"] == -20,
                  "Enabling Constant while muted captured a silent reference.")
        print("PASS: volume modes, output changes, persisted references, mute, and compensation limits.")

        // Read only: this check never changes the user's volume or output device.
        let currentOutput = SystemOutputMonitor.readSnapshot()
        if let decibels = currentOutput.decibels {
            try check(decibels.isFinite || currentOutput.isMuted, "Live output reported invalid volume.")
            print("PASS: read the current output's hardware volume without changing it.")
        } else {
            print("INFO: current output does not expose hardware dB volume; fallback applies.")
        }
    }

    private static func amplitude(decibels: Float) -> Double { pow(10, Double(decibels) / 20) }
}
