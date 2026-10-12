import CoreAudio
import Foundation

/// Reads the default output's volume; it never changes system volume or mute.
final class SystemOutputMonitor: @unchecked Sendable {
    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let queue: DispatchQueue
    private let onChange: @Sendable (SystemOutputVolume) -> Void
    private var listeners: [Listener] = []
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastOutput: SystemOutputVolume?

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
            addListener(object: AudioObjectID(kAudioObjectSystemObject),
                        selector: kAudioHardwarePropertyDefaultOutputDevice,
                        scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
            if device != kAudioObjectUnknown {
                for element in [AudioObjectPropertyElement(kAudioObjectPropertyElementMain)] + Self.stereoChannels(device) {
                    for selector in [kAudioDevicePropertyVolumeDecibels, kAudioDevicePropertyVolumeScalar,
                                     kAudioDevicePropertyMute] {
                        addListener(object: device, selector: selector,
                                    scope: kAudioDevicePropertyScopeOutput, element: element)
                    }
                }
                addListener(object: device, selector: kAudioDevicePropertyPreferredChannelsForStereo,
                            scope: kAudioDevicePropertyScopeOutput, element: kAudioObjectPropertyElementMain)
            }
        }
        let output = Self.readSnapshot(device: device)
        if output != lastOutput { lastOutput = output; onChange(output) }
    }

    static func readSnapshot() -> SystemOutputVolume { readSnapshot(device: defaultOutputDevice()) }

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

    private static func readSnapshot(device: AudioObjectID) -> SystemOutputVolume {
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
        let masterScalar: Float32? = read(device, selector: kAudioDevicePropertyVolumeScalar,
                                         element: kAudioObjectPropertyElementMain, initial: Float32(0))
        let channelScalars: [Float32] = channels.compactMap {
            read(device, selector: kAudioDevicePropertyVolumeScalar, element: $0, initial: Float32(0))
        }
        let muted = masterMute == 1 ||
            (channelMutes.count == channels.count && channelMutes.allSatisfy { $0 == 1 }) ||
            masterScalar.map { $0 <= 0 } == true ||
            (!channelScalars.isEmpty && channelScalars.allSatisfy { $0 <= 0 })
        // Prefer a real master control; otherwise track the louder stereo channel.
        let masterDB: Float32? = read(device, selector: kAudioDevicePropertyVolumeDecibels,
                                     element: kAudioObjectPropertyElementMain, initial: Float32(0))
        let channelDB: [Float32] = channels.compactMap {
            read(device, selector: kAudioDevicePropertyVolumeDecibels, element: $0, initial: Float32(0))
        }
        return SystemOutputVolume(deviceUID: deviceUID, decibels: masterDB ?? channelDB.max(), isMuted: muted)
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
