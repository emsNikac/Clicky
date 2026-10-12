import AVFoundation
import AppKit
import DeveloperToolsSupport
import AudioToolbox
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): message } }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

@main
struct AudioChecks {
    @MainActor
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        try VolumeModeChecks.run()
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let appURL = resources.deletingLastPathComponent().deletingLastPathComponent()
        guard let bundle = Bundle(url: appURL),
              let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else {
            throw CheckFailure.failed("Built app has no system icon metadata.")
        }
        var iconURL = resources.appendingPathComponent(iconName)
        if iconURL.pathExtension.isEmpty { iconURL.appendPathExtension("icns") }
        try check(NSImage(contentsOf: iconURL)?.isValid == true, "Compiled system app icon cannot be decoded.")
        try IconChecks.run(appURL: appURL, iconURL: iconURL)
        let logo = NSImage(resource: ImageResource(name: "ClickyLogo", bundle: bundle))
        let mark = NSImage(resource: ImageResource(name: "ClickyMark", bundle: bundle))
        try check(logo.isValid && mark.isValid, "Header or menu bar logo cannot be decoded from the built bundle.")
        try check(!logo.isTemplate && mark.isTemplate,
                  "Header must keep its colors; menu bar mark must adapt to the menu bar appearance.")
        print("PASS: decoded compiled app icon, header logo, and menu bar template.")
        try check(PhysicalKeyboard.rows.allSatisfy { abs($0.reduce(0) { $0 + $1.width } - 15) < 0.001 },
                  "Keyboard rows must align; a width overflow breaks stereo positioning.")
        let codes = PhysicalKeyboard.rows.flatMap { $0 }.map(\.code)
        try check(Set(codes).count == codes.count, "Two displayed keys share a physical code.")
        try check(PhysicalKeyboard.key(for: 0).pan < 0 && PhysicalKeyboard.key(for: 37).pan > 0,
                  "A and L should be on opposite sides of the stereo image.")
        try check(PhysicalKeyboard.key(for: 49).sampleName == "SPACE", "Space must keep its large-key recording.")
        try check(PhysicalKeyboard.key(for: 12).sampleRow == 3 && PhysicalKeyboard.key(for: 6).sampleRow == 1,
                  "Q and Z must use their correct recorded rows, not reversed rows.")
        try check(PhysicalKeyboard.keys.values.allSatisfy { (-1...1).contains($0.pan) },
                  "A physical key falls outside the valid stereo field.")

        var checkedRecordings = 0
        var sample: AVAudioPCMBuffer?
        var volumeIncreases: [Double] = []
        for profile in SwitchProfile.all {
            var pressSamples: [AVAudioPCMBuffer] = []
            var names = (0...4).map { "press_GENERIC_R\($0)" } + ["release_GENERIC"]
            if profile.hasSpecialKeys {
                names += ["press", "release"].flatMap { action in
                    ["SPACE", "ENTER", "BACKSPACE"].map { "\(action)_\($0)" }
                }
            }
            for name in names {
                let url = resources.appendingPathComponent("\(profile.id)_\(name).mp3")
                let buffers = try RecordingDecoder.decode(url: url)
                try check(buffers.count == 3, "Pitch variants failed for \(url.lastPathComponent).")
                for buffer in buffers {
                    try check(buffer.format.sampleRate == 48_000 && buffer.format.channelCount == 1,
                              "Unexpected playback format for \(url.lastPathComponent).")
                    let data = buffer.floatChannelData![0]
                    let length = Int(buffer.frameLength)
                    try check(length > 48 && length <= 480_000, "Invalid sample duration.")
                    try check((0..<length).allSatisfy { data[$0].isFinite }, "Sample contains nonfinite audio.")
                    let peak = RecordingDecoder.peak(buffer)
                    try check(peak > 0.001, "Recording is silent.")
                    let firstAudible = (0..<length).first { abs(data[$0]) > peak * 0.01 } ?? length
                    try check(firstAudible < 960, "Recording retains more than 20 ms of lead-in silence.")
                    try check(abs(data[length - 1]) < 0.0001, "Trimmed sample ends abruptly.")
                }
                if profile.id == "blackink" && name == "press_GENERIC_R2" { sample = buffers[1] }
                if name.hasPrefix("press_GENERIC") { pressSamples.append(buffers[1]) }
                checkedRecordings += 1
            }
            // Match the app's existing pack normalization, then compare the old and new full-volume paths.
            let reference = pressSamples.map(RecordingDecoder.peak).max()!
            let packGain = min(6, 0.7 / max(reference, 0.01))
            let key = pressSamples[2]
            for frame in 0..<Int(key.frameLength) { key.floatChannelData![0][frame] *= packGain }
            let previous = try render(sample: key, pan: 0, voiceCount: 1,
                                      settings: PlaybackSettings(volume: 1), legacyFullVolume: true)
            let current = try render(sample: key, pan: 0, voiceCount: 1,
                                     settings: PlaybackSettings(volume: 1))
            let increase = 10 * log10((current.leftEnergy + current.rightEnergy) /
                                     (previous.leftEnergy + previous.rightEnergy))
            try check(increase >= 6, "\(profile.name) is still too quiet at full volume: +\(increase) dB.")
            try check(current.peak <= 1.01, "\(profile.name) clips at full volume: \(current.peak).")
            volumeIncreases.append(increase)

            let constant = PlaybackSettings(volume: 0.25, volumeMode: .constant, variation: false)
            let referenceClick = try render(sample: key, pan: 0, voiceCount: 8, settings: constant)
            for gain: Float in [-48, -24, -18, -6] {
                let changed = try render(sample: key, pan: 0, voiceCount: 8, gain: gain, settings: constant)
                try checkSameWaveform(referenceClick, changed, scale: pow(10, Double(-gain) / 20),
                                      message: "\(profile.name) changed texture during \(gain) dB Constant compensation.")
                try check(changed.peak <= 1.01, "Constant compensation clips for \(profile.name).")
            }
            for volume: Float in [0.15, 0.6, 1] {
                let changed = try render(sample: key, pan: 0, voiceCount: 8,
                                         settings: PlaybackSettings(volume: volume, variation: false))
                try checkSameWaveform(referenceClick, changed, scale: 1 / Double(volume),
                                      message: "\(profile.name) changed texture when app volume changed.")
            }
        }
        try check(checkedRecordings == 150, "A required recording was skipped.")
        print("PASS: 150 recordings decoded, trimmed, and checked for valid audio.")
        print(String(format: "PASS: full-volume output increased by %.1f–%.1f dB across all 13 profiles.",
                     volumeIncreases.min()!, volumeIncreases.max()!))
        print("PASS: Constant compensation and app volume preserve click waveforms across all 13 profiles.")

        guard let sample else { throw CheckFailure.failed("Missing stereo test sample.") }
        let left = try render(sample: sample, pan: -0.8, voiceCount: 1)
        let right = try render(sample: sample, pan: 0.8, voiceCount: 1)
        try check(left.leftEnergy > left.rightEnergy * 2, "Left-hand key is not spatialized left.")
        try check(right.rightEnergy > right.leftEnergy * 2, "Right-hand key is not spatialized right.")
        let burst = try render(sample: sample, pan: 0, voiceCount: 32)
        try check(burst.peak > 0.01 && burst.peak <= 1.01, "32-voice burst is silent or clips: \(burst.peak).")
        let baseline = try render(sample: sample, pan: 0, voiceCount: 1)
        let compensated = try render(sample: sample, pan: 0, voiceCount: 1, gain: -12)
        let originalAudibleEnergy = baseline.leftEnergy * pow(10, -30.0 / 10)
        let raisedSystemAudibleEnergy = compensated.leftEnergy * pow(10, -18.0 / 10)
        try check(abs(originalAudibleEnergy - raisedSystemAudibleEnergy) / originalAudibleEnergy < 0.001,
                  "Rendered clicks got louder despite compensation for a 12 dB system increase.")
        let constant = PlaybackSettings(volume: 0.28, volumeMode: .constant, thresholdStage: 3, variation: false)
        let atThreshold = try render(sample: sample, pan: 0, voiceCount: 8, settings: constant)
        var compensation = VolumeCompensation()
        for macVolume in (1...16).map({ Float($0) / 16 }) + [0.18, 0.19, 0.53, 0.99] {
            let output = VolumeModeChecks.speakerOutput(scalar: macVolume)
            compensation.update(mode: .constant, output: output, thresholdStage: 3)
            let changed = try render(sample: sample, pan: 0, voiceCount: 8, gain: compensation.gain,
                                     settings: constant)
            let aboveThresholdDB = max(0, output.decibels! - VolumeModeChecks.speakerStages[2])
            try checkSameWaveform(atThreshold, changed, scale: pow(10, Double(aboveThresholdDB) / 20),
                                  message: "Rendered stage-3 threshold changed level or texture at Mac volume \(macVolume * 100)%.")
        }
        let differentGradientVolume = try render(sample: sample, pan: 0, voiceCount: 8,
            settings: PlaybackSettings(volume: 0.9, volumeMode: .constant, thresholdStage: 3, variation: false))
        try checkSameWaveform(atThreshold, differentGradientVolume, scale: 1,
                              message: "Saved Gradient volume changed the Constant threshold level.")
        print("PASS: rendered stage-3 ceiling across all 16 system stages and fractional values; click texture is preserved.")
        let silent = try render(sample: sample, pan: 0, voiceCount: 1, settings: PlaybackSettings(volume: 0))
        try check(silent.peak == 0, "Zero app volume is no longer silent.")
        let muted = try render(sample: sample, pan: 0, voiceCount: 1,
                               settings: PlaybackSettings(volume: 1, volumeMode: .constant), outputMuted: true)
        try check(muted.peak == 0, "Constant mode ignored output mute.")
        print("PASS: offline stereo placement and 32-voice limiting.")
        print("PASS: rendered constant loudness, independent Gradient volume, and mute.")
        print("PASS: keyboard geometry, row mappings, and special key selection.")
    }

    private static func render(sample: AVAudioPCMBuffer, pan: Float, voiceCount: Int, gain: Float = 0,
                               settings: PlaybackSettings = PlaybackSettings(volume: 0.15),
                               outputMuted: Bool = false,
                               legacyFullVolume: Bool = false) throws
        -> (leftEnergy: Double, rightEnergy: Double, peak: Float, waveform: [Float]) {
        let engine = AVAudioEngine()
        let mixer = AVAudioMixerNode()
        let equalizer = PlaybackSettings.makeEqualizer()
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        engine.attach(mixer)
        engine.attach(equalizer)
        engine.attach(limiter)
        engine.connect(mixer, to: equalizer, format: nil)
        engine.connect(equalizer, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        let players = (0..<voiceCount).map { _ -> AVAudioPlayerNode in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: sample.format)
            return player
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        func applySettings() {
            settings.apply(to: mixer, equalizer: equalizer, output: engine.mainMixerNode,
                           compensationGain: gain, outputMuted: outputMuted)
            if legacyFullVolume {
                // The original quieter graph: fixed 0.65 attenuation before EQ/limiting,
                // no 9 dB loudness boost, and no final output headroom adjustment.
                mixer.outputVolume = 0.65
                equalizer.globalGain = 0
                engine.mainMixerNode.outputVolume = 1
            }
        }
        applySettings()
        try engine.start()
        defer { engine.stop() }
        applySettings()
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        // Let the audio units' smoothed gain controls settle before measuring a click.
        for _ in 0..<20 { _ = try engine.renderOffline(512, to: output) }
        for player in players {
            player.pan = pan
            player.scheduleBuffer(sample)
            player.play()
        }
        var left = 0.0, right = 0.0
        var peak: Float = 0
        var waveform: [Float] = []
        for _ in 0..<40 {
            let status = try engine.renderOffline(512, to: output)
            try check(status == .success || status == .insufficientDataFromInputNode,
                      "Offline audio render failed: \(status.rawValue).")
            for frame in 0..<Int(output.frameLength) {
                let l = output.floatChannelData![0][frame]
                let r = output.floatChannelData![1][frame]
                try check(l.isFinite && r.isFinite, "Audio graph produced nonfinite output.")
                left += Double(l * l)
                right += Double(r * r)
                peak = max(peak, abs(l), abs(r))
                waveform.append(contentsOf: [l, r])
            }
        }
        return (left, right, peak, waveform)
    }

    private static func checkSameWaveform(
        _ reference: (leftEnergy: Double, rightEnergy: Double, peak: Float, waveform: [Float]),
        _ changed: (leftEnergy: Double, rightEnergy: Double, peak: Float, waveform: [Float]),
        scale: Double, message: String
    ) throws {
        try check(reference.waveform.count == changed.waveform.count, "Rendered click lengths differ.")
        let error = zip(reference.waveform, changed.waveform).reduce(0.0) {
            let difference = Double($1.0) - Double($1.1) * scale
            return $0 + difference * difference
        }
        let energy = reference.leftEnergy + reference.rightEnergy
        try check(energy > 0.000001, "Waveform comparison was silent.")
        try check(error / energy < 0.00001, "\(message) Relative waveform error: \(error / energy).")
    }
}
