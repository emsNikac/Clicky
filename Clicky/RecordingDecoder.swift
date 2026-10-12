import AVFoundation

enum SoundEngineError: LocalizedError {
    case missingRecording(String)
    case invalidRecording(String)
    var errorDescription: String? {
        switch self {
        case .missingRecording(let name): "Missing recording: \(name). Rebuild with the bundled sound resources."
        case .invalidRecording(let name): "Could not decode recording: \(name)."
        }
    }
}

enum RecordingDecoder {
    static func decode(url: URL) throws -> [AVAudioPCMBuffer] {
        let filename = url.lastPathComponent
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length < 480_000,
              let original = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                              frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SoundEngineError.invalidRecording(filename)
        }
        try file.read(into: original)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity:
                AVAudioFrameCount(Double(original.frameLength) * 48_000 / file.processingFormat.sampleRate) + 1024)
        else { throw SoundEngineError.invalidRecording(filename) }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return original
        }
        if let error { throw error }
        guard status != .error, converted.frameLength > 0 else {
            throw SoundEngineError.invalidRecording(filename)
        }
        let data = converted.floatChannelData![0]
        let count = Int(converted.frameLength)
        let peak = Self.peak(converted)
        guard peak > 0.00001 else { throw SoundEngineError.invalidRecording(filename) }
        // Remove MP3 lead-in silence, retaining 0.5 ms before the first transient.
        let threshold = max(0.0003, peak * 0.008)
        let first = (0..<count).first { abs(data[$0]) > threshold } ?? 0
        let last = (0..<count).last { abs(data[$0]) > threshold * 0.25 } ?? count - 1
        let start = max(0, first - 24)
        let end = min(count, last + 240)
        return [0.992, 1.0, 1.008].map { rate in
            let length = max(1, Int(Double(end - start) / rate))
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
            buffer.frameLength = AVAudioFrameCount(length)
            let output = buffer.floatChannelData![0]
            for frame in 0..<length {
                let position = Double(start) + Double(frame) * rate
                let index = min(end - 1, Int(position))
                let fraction = Float(position - Double(index))
                output[frame] = data[index] * (1 - fraction) + data[min(end - 1, index + 1)] * fraction
                // A short tail fade prevents an edit boundary from clicking.
                output[frame] *= min(1, Float(length - 1 - frame) / 48)
            }
            return buffer
        }
    }

    static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        let data = buffer.floatChannelData![0]
        return (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(data[$1])) }
    }
}
