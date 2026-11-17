import AVFoundation
import Core

/// Records the default input device as 16 kHz mono, the format Whisper expects.
@MainActor
public final class MicRecorder: AudioRecorder {
    public static let sampleRate = AudioClip.speechSampleRate

    private let engine = AVAudioEngine()
    private let trimmer = SilenceTrimmer()
    /// This recording's audio; kept after `stop` so the last audio can still be taken.
    private var buffer: ConvertingBuffer?
    private var isRecording = false

    public var onAudio: (() -> Void)?

    public init() {}

    public func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw MicRecorderError.noInputDevice }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let buffer = ConvertingBuffer(from: inputFormat, to: targetFormat, onAppend: Self.announcer(for: self))
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
        isRecording = true
    }

    /// Loudness of the most recent audio, in dBFS (`SilenceTrimmer.silentDecibels` when not recording).
    public var currentDecibels: Float {
        isRecording ? buffer?.latestDecibels ?? SilenceTrimmer.silentDecibels : SilenceTrimmer.silentDecibels
    }

    public func stop() async -> AudioClip {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        let samples = buffer?.allSamples() ?? []
        return trimmer.trim(AudioClip(samples: samples, sampleRate: Self.sampleRate))
    }

    public func takeAudio() -> [Float] {
        buffer?.takeNew() ?? []
    }
}

extension MicRecorder {
    /// Built outside the main actor: the tap runs on the audio render thread, and a closure
    /// formed in a @MainActor method would inherit that isolation and trap at runtime.
    /// Called on the render thread after each tapped buffer (~85 ms): tells `onAudio` on the main queue, in order.
    nonisolated private static func announcer(for recorder: MicRecorder) -> @Sendable () -> Void {
        { [weak recorder] in
            DispatchQueue.main.async { MainActor.assumeIsolated { recorder?.onAudio?() } }
        }
    }

    nonisolated private static func tapBlock(appendingTo buffer: ConvertingBuffer) -> AVAudioNodeTapBlock {
        { pcm, _ in buffer.append(pcm) }
    }
}

public enum MicRecorderError: Error {
    case noInputDevice
    case unsupportedFormat
}

/// Converts tapped buffers to the target format and accumulates samples.
/// Appended from the audio render thread, read on the main actor.
private final class ConvertingBuffer: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let onAppend: @Sendable () -> Void
    private let lock = NSLock()
    private var samples: [Float] = []
    /// How many samples `takeNew()` has handed out.
    private var taken = 0
    private var decibels: Float = SilenceTrimmer.silentDecibels

    init?(from source: AVAudioFormat, to target: AVAudioFormat, onAppend: @escaping @Sendable () -> Void) {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        self.converter = converter
        self.targetFormat = target
        self.onAppend = onAppend
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
        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        samples.append(contentsOf: chunk)
        decibels = SilenceTrimmer.decibels(ArraySlice(chunk))
        onAppend()
    }

    var latestDecibels: Float {
        lock.lock()
        defer { lock.unlock() }
        return decibels
    }

    /// The whole recording.
    func allSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// The samples appended since the last call.
    func takeNew() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let new = Array(samples[taken...])
        taken = samples.count
        return new
    }
}
