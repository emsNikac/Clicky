import AVFoundation
import Foundation

struct PlaybackSettings: Sendable {
    static let maximumVolumeGainDB: Float = 9
    static let outputHeadroom: Float = 0.9

    var volume: Float = 0.6
    var volumeMode: VolumeMode = .gradient
    var thresholdStage: Int = VolumeControls.defaultThreshold
    var width: Float = 0.85
    var depth: Float = 1
    var releaseLevel: Float = 1
    var variation = true

    static func makeEqualizer() -> AVAudioUnitEQ {
        let equalizer = AVAudioUnitEQ(numberOfBands: 2)
        equalizer.bands[0].filterType = .lowShelf
        equalizer.bands[0].frequency = 250
        equalizer.bands[1].filterType = .highShelf
        equalizer.bands[1].frequency = 3_000
        equalizer.bands.forEach { $0.bypass = false }
        return equalizer
    }

    func apply(to mixer: AVAudioMixerNode, equalizer: AVAudioUnitEQ, output: AVAudioMixerNode,
               compensationGain: Float, outputMuted: Bool) {
        // Keep the limiter's input independent of app and system volume. Changing
        // its drive changes the attack and texture of the recorded switches.
        equalizer.globalGain = Self.maximumVolumeGainDB
        equalizer.bands[0].gain = (depth - 0.5) * 10
        equalizer.bands[1].gain = (depth - 0.5) * -8
        mixer.outputVolume = 1
        applyOutputVolume(to: output, compensationGain: compensationGain, outputMuted: outputMuted)
    }

    func applyOutputVolume(to output: AVAudioMixerNode, compensationGain: Float, outputMuted: Bool) {
        // A Constant threshold represents the Mac's volume stage directly. Its
        // level must not also be multiplied by a hidden Gradient percentage.
        let baseVolume: Float = volumeMode == .constant ? 1 : volume
        let compensatedVolume = baseVolume * pow(10, min(0, compensationGain) / 20)
        // Leave 0.9 dB after the limiter for its small transient overshoot.
        // Compensation cannot exceed the remaining output headroom.
        output.outputVolume = Self.outputHeadroom * min(1, max(0, compensatedVolume)) *
            (volumeMode == .constant && outputMuted ? 0 : 1)
    }
}
