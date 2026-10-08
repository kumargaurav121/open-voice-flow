import AVFoundation
import Core

/// Records the default input device as 16 kHz mono, the format Whisper expects.
@MainActor
public final class MicRecorder: AudioRecorder {
    public static let sampleRate = AudioClip.speechSampleRate

    private let engine = AVAudioEngine()
    private let trimmer = SilenceTrimmer()
    private var buffer: ConvertingBuffer?

    public init() {}

    public func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw MicRecorderError.noInputDevice }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let buffer = ConvertingBuffer(from: inputFormat, to: targetFormat)
        else { throw MicRecorderError.unsupportedFormat }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: Self.tapBlock(appendingTo: buffer))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.buffer = buffer
    }

    public func stop() async -> AudioClip {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = buffer?.drain() ?? []
        buffer = nil
        return trimmer.trim(AudioClip(samples: samples, sampleRate: Self.sampleRate))
    }
}

extension MicRecorder {
    /// Built outside the main actor: the tap runs on the audio render thread, and a closure
    /// formed in a @MainActor method would inherit that isolation and trap at runtime.
    nonisolated private static func tapBlock(appendingTo buffer: ConvertingBuffer) -> AVAudioNodeTapBlock {
        { pcm, _ in buffer.append(pcm) }
    }
}

public enum MicRecorderError: Error {
    case noInputDevice
    case unsupportedFormat
}

/// Converts tapped buffers to the target format and accumulates samples.
/// Appended from the audio render thread, drained on the main actor.
private final class ConvertingBuffer: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var samples: [Float] = []

    init?(from source: AVAudioFormat, to target: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        self.converter = converter
        self.targetFormat = target
    }

    func append(_ pcm: AVAudioPCMBuffer) {
        let ratio = targetFormat.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        lock.lock()
        defer { lock.unlock() }
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return pcm
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let drained = samples
        samples = []
        return drained
    }
}
