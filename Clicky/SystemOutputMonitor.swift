import CoreAudio
import Foundation

/// Reads the default output's volume; it never changes system volume or mute.
final class SystemOutputMonitor: @unchecked Sendable {
    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private struct CurveCache {
        let device: AudioObjectID
        let element: AudioObjectPropertyElement
        let stages: [Float]?
    }

    private let queue: DispatchQueue
    private let onChange: @Sendable (SystemOutputVolume) -> Void
    private var listeners: [Listener] = []
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastOutput: SystemOutputVolume?
    private var curveCache: CurveCache?

    init(queue: DispatchQueue, onChange: @escaping @Sendable (SystemOutputVolume) -> Void) {
        self.queue = queue
        self.onChange = onChange
        queue.async { [weak self] in self?.refresh(reinstallListeners: true) }
    }

    deinit { removeListeners() }

    // Called on the audio queue after an engine/device reconfiguration.
    func refresh(reinstallListeners: Bool = false) {
        let newDevice = Self.defaultOutputDevice()
        if newDevice != device || reinstallListeners {
            removeListeners()
            device = newDevice
            curveCache = nil
            addListener(object: AudioObjectID(kAudioObjectSystemObject),
                        selector: kAudioHardwarePropertyDefaultOutputDevice,
                        scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
            if device != kAudioObjectUnknown {
                for element in [AudioObjectPropertyElement(kAudioObjectPropertyElementMain)] + Self.stereoChannels(device) {
                    for selector in [kAudioDevicePropertyVolumeDecibels, kAudioDevicePropertyVolumeScalar,
                                     kAudioDevicePropertyMute, kAudioDevicePropertyVolumeRangeDecibels] {
                        addListener(object: device, selector: selector,
                                    scope: kAudioDevicePropertyScopeOutput, element: element)
                    }
                }
                addListener(object: device, selector: kAudioDevicePropertyPreferredChannelsForStereo,
                            scope: kAudioDevicePropertyScopeOutput, element: kAudioObjectPropertyElementMain)
            }
        }
        let output = Self.readSnapshot(device: device, curveCache: &curveCache)
        if output != lastOutput { lastOutput = output; onChange(output) }
    }

    static func readSnapshot() -> SystemOutputVolume {
        var cache: CurveCache?
        return readSnapshot(device: defaultOutputDevice(), curveCache: &cache)
    }

    static func stageCurve(minimum: Float, maximum: Float,
                           decibelsToScalar: (Float) -> Float?) -> [Float]? {
        guard minimum.isFinite, maximum.isFinite, minimum >= -160, maximum <= 24, minimum < maximum,
              let lowScalar = decibelsToScalar(minimum), let highScalar = decibelsToScalar(maximum),
              lowScalar.isFinite, highScalar.isFinite, lowScalar >= 0, lowScalar < highScalar,
              lowScalar <= VolumeControls.scalar(for: 1), abs(highScalar - 1) <= 0.01 else { return nil }
        var previous = lowScalar
        for index in 1...VolumeControls.stageCount {
            let decibels = minimum + (maximum - minimum) * Float(index) / Float(VolumeControls.stageCount)
            guard let scalar = decibelsToScalar(decibels), scalar.isFinite,
                  (0...1).contains(scalar), scalar >= previous else { return nil }
            previous = scalar
        }
        var stages: [Float] = []
        for stage in VolumeControls.stageRange {
            let target = VolumeControls.scalar(for: stage)
            var lower = minimum, upper = maximum
            // Invert the device's dB-to-slider mapping. Some built-in drivers'
            // forward conversion disagrees with their actual dB getter; the
            // reverse conversion matches it. Do not assume slider positions
            // are linear audio gains or linear dB values.
            for _ in 0..<20 {
                let middle = (lower + upper) / 2
                guard let scalar = decibelsToScalar(middle), scalar.isFinite,
                      (0...1).contains(scalar) else { return nil }
                if scalar < target { lower = middle } else { upper = middle }
            }
            stages.append(stage == VolumeControls.stageCount ? maximum : (lower + upper) / 2)
        }
        guard zip(stages, stages.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
        return stages
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr else { return AudioObjectID(kAudioObjectUnknown) }
        return device
    }

    private static func stereoChannels(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
                                                mScope: kAudioDevicePropertyScopeOutput,
                                                mElement: kAudioObjectPropertyElementMain)
        var channels: [UInt32] = [1, 2]
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        let status = channels.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? Array(Set(channels)).sorted() : [1, 2]
    }

    private static func readSnapshot(device: AudioObjectID, curveCache: inout CurveCache?) -> SystemOutputVolume {
        guard device != kAudioObjectUnknown else { return SystemOutputVolume() }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let uid else { return SystemOutputVolume() }
        let deviceUID = uid.takeRetainedValue() as String
        let channels = stereoChannels(device)
        let masterMute: UInt32? = read(device, selector: kAudioDevicePropertyMute,
                                      element: kAudioObjectPropertyElementMain, initial: UInt32(0))
        let channelMutes: [UInt32] = channels.compactMap {
            read(device, selector: kAudioDevicePropertyMute, element: $0, initial: UInt32(0))
        }
        let level = volumeLevel(device)
        let channelScalars: [Float32] = channels.compactMap {
            read(device, selector: kAudioDevicePropertyVolumeScalar, element: $0, initial: Float32(0))
        }
        let muted = masterMute == 1 ||
            (channelMutes.count == channels.count && channelMutes.allSatisfy { $0 == 1 }) ||
            level.scalar.map { $0 <= 0 } == true ||
            (!channelScalars.isEmpty && channelScalars.allSatisfy { $0 <= 0 })
        if curveCache?.device != device || curveCache?.element != level.element {
            let range: AudioValueRange? = read(device, selector: kAudioDevicePropertyVolumeRangeDecibels,
                                               element: level.element, initial: AudioValueRange())
            let stages = range.flatMap { range in
                stageCurve(minimum: Float(range.mMinimum), maximum: Float(range.mMaximum)) {
                    read(device, selector: kAudioDevicePropertyVolumeDecibelsToScalar,
                         element: level.element, initial: $0)
                }
            }
            curveCache = CurveCache(device: device, element: level.element, stages: stages)
        }
        var stages = curveCache?.stages
        if let scalar = level.scalar, let decibels = level.decibels,
           let converted: Float = read(device, selector: kAudioDevicePropertyVolumeDecibelsToScalar,
                                       element: level.element, initial: decibels),
           !converted.isFinite || abs(converted - scalar) > 0.01 {
            stages = nil
        }
        return SystemOutputVolume(deviceUID: deviceUID, decibels: level.decibels, scalar: level.scalar,
                                  stageDecibels: stages, isMuted: muted)
    }

    private static func volumeLevel(_ device: AudioObjectID)
        -> (element: AudioObjectPropertyElement, scalar: Float?, decibels: Float?) {
        func level(_ element: AudioObjectPropertyElement)
            -> (element: AudioObjectPropertyElement, scalar: Float?, decibels: Float?) {
            let scalar: Float? = read(device, selector: kAudioDevicePropertyVolumeScalar,
                                      element: element, initial: Float(0))
            let decibels: Float? = read(device, selector: kAudioDevicePropertyVolumeDecibels,
                                        element: element, initial: Float(0))
            return (element, scalar.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil },
                    decibels.flatMap { $0.isFinite && (-160...24).contains($0) ? $0 : nil })
        }
        // Read both representations from the same control. Mixing a master dB
        // control with a channel's scalar would give the wrong compensation.
        let master = level(kAudioObjectPropertyElementMain)
        if master.scalar != nil || master.decibels != nil { return master }
        let channels = stereoChannels(device).map(level)
        if let loudest = channels.filter({ $0.decibels != nil }).max(by: { $0.decibels! < $1.decibels! }) {
            return loudest
        }
        return channels.max { ($0.scalar ?? 0) < ($1.scalar ?? 0) } ?? master
    }

    private static func read<T>(_ device: AudioObjectID, selector: AudioObjectPropertySelector,
                                element: AudioObjectPropertyElement, initial: T) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) == noErr ? $0.pointee : nil
        }
    }

    private func addListener(object: AudioObjectID, selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] count, addresses in
            let layoutChanged = (0..<Int(count)).contains {
                addresses[$0].mSelector == kAudioDevicePropertyPreferredChannelsForStereo
                    || addresses[$0].mSelector == kAudioDevicePropertyVolumeRangeDecibels
            }
            self?.refresh(reinstallListeners: layoutChanged)
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
            listeners.append(Listener(object: object, address: address, block: block))
        }
    }

    private func removeListeners() {
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, queue, listener.block)
        }
        listeners.removeAll()
    }
}
