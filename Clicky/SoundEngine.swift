import AVFoundation
import AudioToolbox

struct PlaybackSettings: Sendable {
    var volume: Float = 0.6
    var volumeMode: VolumeMode = .gradient
    var width: Float = 0.85
    var depth: Float = 1
    var releaseLevel: Float = 1
    var variation = true
}

/// All engine state lives on one serial queue. Files are decoded before typing begins.
final class SoundEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.projects.Clicky.audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 2)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var samples: [String: [AVAudioPCMBuffer]] = [:]
    private var profileID = ""
    private var nextVoice = 0
    private var settings = PlaybackSettings()
    private var configurationObserver: NSObjectProtocol?
    private var outputMonitor: SystemOutputMonitor?
    private var outputVolume = SystemOutputVolume()
    private var compensation = VolumeCompensation(references:
        (UserDefaults.standard.dictionary(forKey: "constantVolumeReferences") ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.floatValue })
    private var hasConfiguredSettings = false
    private var resetVolumeReference = false
    var onError: (@Sendable (String) -> Void)?
    var onVolumeStatus: (@Sendable (ConstantVolumeStatus) -> Void)?

    init() {
        engine.attach(mixer)
        engine.attach(equalizer)
        engine.attach(limiter)
        engine.connect(mixer, to: equalizer, format: nil)
        engine.connect(equalizer, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        for _ in 0..<32 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            players.append(player)
        }
        equalizer.bands[0].filterType = .lowShelf
        equalizer.bands[0].frequency = 250
        equalizer.bands[1].filterType = .highShelf
        equalizer.bands[1].frequency = 3_000
        equalizer.bands.forEach { $0.bypass = false }
        outputMonitor = SystemOutputMonitor(queue: queue) { [weak self] output in
            guard let self else { return }
            self.outputVolume = output
            self.updateVolumeCompensation()
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, !self.samples.isEmpty else { return }
                self.outputMonitor?.refresh(reinstallListeners: true)
                do { try self.startEngine() } catch { self.onError?(error.localizedDescription) }
            }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    func configure(_ settings: PlaybackSettings) {
        queue.async { [self] in
            if hasConfiguredSettings, self.settings.volumeMode != settings.volumeMode,
               settings.volumeMode == .constant { resetVolumeReference = true }
            if settings.volumeMode == .gradient { resetVolumeReference = false }
            self.settings = settings
            hasConfiguredSettings = true
            outputMonitor?.refresh()
            updateVolumeCompensation()
            equalizer.bands[0].gain = (settings.depth - 0.5) * 10
            equalizer.bands[1].gain = (settings.depth - 0.5) * -8
        }
    }

    func load(_ profile: SwitchProfile, completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            do {
                var decoded: [String: [AVAudioPCMBuffer]] = [:]
                for row in 0...4 {
                    let name = "press_GENERIC_R\(row)"
                    decoded[name] = try decode(profile.id, name: name)
                }
                decoded["release_GENERIC"] = try decode(profile.id, name: "release_GENERIC")
                if profile.hasSpecialKeys {
                    for action in ["press", "release"] {
                        for key in ["SPACE", "ENTER", "BACKSPACE"] {
                            let name = "\(action)_\(key)"
                            decoded[name] = try decode(profile.id, name: name)
                        }
                    }
                }
                // Match packs as a whole, keeping real differences between their keys.
                let peaks = (0...4).compactMap { decoded["press_GENERIC_R\($0)"]?.first }.map(RecordingDecoder.peak)
                let reference = peaks.max() ?? 1
                let gain = min(6, 0.7 / max(reference, 0.01))
                for buffers in decoded.values {
                    for buffer in buffers {
                        let channel = buffer.floatChannelData![0]
                        for frame in 0..<Int(buffer.frameLength) { channel[frame] *= gain }
                    }
                }
                players.forEach { $0.stop() }
                samples = decoded
                profileID = profile.id
                try startEngine()
                completion(nil)
            } catch {
                // Do not play the previous switch under the newly selected switch name.
                players.forEach { $0.stop() }
                samples.removeAll()
                profileID = ""
                completion(error.localizedDescription)
            }
        }
    }

    func play(_ stroke: KeyStroke, profileID requestedProfile: String) {
        queue.async { [self] in
            guard requestedProfile == profileID, engine.isRunning else { return }
            let key = PhysicalKeyboard.key(for: stroke.code)
            let action = stroke.isDown ? "press" : "release"
            let generic = stroke.isDown ? "press_GENERIC_R\(key.sampleRow)" : "release_GENERIC"
            let name = key.sampleName.map { "\(action)_\($0)" } ?? generic
            guard let variants = samples[name] ?? samples[generic] else { return }
            guard stroke.isDown || settings.releaseLevel > 0 else { return }
            let buffer = variants[settings.variation ? Int.random(in: variants.indices) : 1]
            let player = players[nextVoice]
            nextVoice = (nextVoice + 1) % players.count
            player.stop()
            player.pan = max(-1, min(1, key.pan * settings.width))
            let distance: Float = 1 - Float(5 - key.row) * 0.018 * settings.width
            let variation: Float = settings.variation ? Float.random(in: 0.94...1.0) : 1
            player.volume = distance * variation * (stroke.isDown ? 1 : settings.releaseLevel)
            player.scheduleBuffer(buffer)
            player.play()
        }
    }

    func silence() { queue.async { [self] in players.forEach { $0.stop() } } }

    private func updateVolumeCompensation() {
        let previousReferences = compensation.references
        compensation.update(mode: settings.volumeMode, output: outputVolume, resetReference: resetVolumeReference)
        if settings.volumeMode == .constant, compensation.status == .active || compensation.status == .limited {
            resetVolumeReference = false
        }
        if compensation.references != previousReferences {
            UserDefaults.standard.set(compensation.references, forKey: "constantVolumeReferences")
        }
        // Compensate before the limiter so low system volume cannot cause digital clipping.
        equalizer.globalGain = compensation.gain
        mixer.outputVolume = settings.volume * 0.65 *
            (settings.volumeMode == .constant && outputVolume.isMuted ? 0 : 1)
        onVolumeStatus?(compensation.status)
    }

    private func startEngine() throws {
        if !engine.isRunning { engine.prepare(); try engine.start() }
    }

    private func decode(_ pack: String, name: String) throws -> [AVAudioPCMBuffer] {
        let filename = "\(pack)_\(name)"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else {
            throw SoundEngineError.missingRecording(filename)
        }
        return try RecordingDecoder.decode(url: url)
    }
}
