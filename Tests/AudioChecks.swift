import AVFoundation
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
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
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
        for profile in SwitchProfile.all {
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
                checkedRecordings += 1
            }
        }
        try check(checkedRecordings == 150, "A required recording was skipped.")
        print("PASS: 150 recordings decoded, trimmed, and checked for valid audio.")

        guard let sample else { throw CheckFailure.failed("Missing stereo test sample.") }
        let left = try render(sample: sample, pan: -0.8, voiceCount: 1)
        let right = try render(sample: sample, pan: 0.8, voiceCount: 1)
        try check(left.leftEnergy > left.rightEnergy * 2, "Left-hand key is not spatialized left.")
        try check(right.rightEnergy > right.leftEnergy * 2, "Right-hand key is not spatialized right.")
        let burst = try render(sample: sample, pan: 0, voiceCount: 32)
        try check(burst.peak > 0.01 && burst.peak <= 1.01, "32-voice burst is silent or clips: \(burst.peak).")
        print("PASS: offline stereo placement and 32-voice limiting.")
        print("PASS: keyboard geometry, row mappings, and special key selection.")
    }

    private static func render(sample: AVAudioPCMBuffer, pan: Float, voiceCount: Int) throws
        -> (leftEnergy: Double, rightEnergy: Double, peak: Float) {
        let engine = AVAudioEngine()
        let mixer = AVAudioMixerNode()
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        engine.attach(mixer)
        engine.attach(limiter)
        engine.connect(mixer, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        let players = (0..<voiceCount).map { _ -> AVAudioPlayerNode in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: sample.format)
            return player
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        defer { engine.stop() }
        for player in players {
            player.pan = pan
            player.scheduleBuffer(sample)
            player.play()
        }
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        var left = 0.0, right = 0.0
        var peak: Float = 0
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
            }
        }
        return (left, right, peak)
    }
}
