import AVFoundation

enum RecorderError: LocalizedError {
    case noInput, converter
    var errorDescription: String? {
        switch self {
        case .noInput: return "No microphone input is available."
        case .converter: return "Could not create the audio converter."
        }
    }
}

/// Captures microphone audio and converts it to 16 kHz mono Float32, the format Whisper expects.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Called on an audio thread with an RMS level in 0...1.
    var onLevel: ((Float) -> Void)?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { throw RecorderError.noInput }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { throw RecorderError.converter }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer, outFormat: outFormat)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops capture and returns the recorded 16 kHz samples.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); defer { lock.unlock() }
        let out = samples
        samples.removeAll()
        return out
    }

    private func process(_ buffer: AVAudioPCMBuffer, outFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData?[0] else { return }
        let n = Int(out.frameLength)
        let chunk = UnsafeBufferPointer(start: ch, count: n)

        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = n > 0 ? sqrt(sum / Float(n)) : 0
        onLevel?(min(1, rms * 8))

        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
    }
}
