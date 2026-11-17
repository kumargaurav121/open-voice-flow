import AVFoundation
import Core
import CoreAudio

/// Records the default input device as 16 kHz mono, the format Whisper expects.
///
/// The microphone is set up ahead of time (`prepare`), so pressing the key only switches it on and the first
/// word isn't lost: the tap is installed and the engine prepared but not running, and between recordings
/// it is paused, which stops the hardware (and the macOS microphone indicator) but keeps that setup.
@MainActor
public final class MicRecorder: AudioRecorder {
    public static let sampleRate = AudioClip.speechSampleRate

    private var engine = AVAudioEngine()
    private let trimmer = SilenceTrimmer()
    /// The recording's audio, reused for each one; kept after `stop` so the last audio can still be taken.
    private var buffer: ConvertingBuffer?
    /// The input format the tap was installed with; nil until set up.
    private var tapFormat: AVAudioFormat?
    /// The default input device when it was set up.
    private var device: AudioDeviceID?
    private var isRecording = false
    private var configurationObserver: NSObjectProtocol?

    public var onAudio: (() -> Void)?
    /// Something worth a line in the app log (the microphone was set up again, or couldn't be).
    public var onNote: ((String) -> Void)?
    /// Host time when the last recording was asked to start (key down).
    private var startedAt: UInt64 = 0
    /// Whether the last recording found the microphone already set up (otherwise it set it up on the press).
    public private(set) var lastStartWasReady = false

    public init() {
        observe(engine)
    }

    /// A new input format, or a device change while running: the engine has stopped and the tap is stale.
    private func observe(_ engine: AVAudioEngine) {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputChanged() }
        }
    }

    /// Sets the microphone up so a recording only has to switch it on. Does nothing until microphone access
    /// is granted (touching the input earlier could ask for it before onboarding does); a recording then
    /// sets it up itself.
    public func prepare() {
        guard tapFormat == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        try? setUp()
    }

    /// How long after key down the last recording's first sample was captured: audio spoken before then is lost.
    public var firstAudioDelay: TimeInterval? {
        buffer?.firstCaptured.map { AVAudioTime.seconds(forHostTime: $0) - AVAudioTime.seconds(forHostTime: startedAt) }
    }

    public func start() throws {
        startedAt = mach_absolute_time()
        // The change notification can miss a switch made while paused (another mic with the same format).
        lastStartWasReady = tapFormat != nil && Self.defaultInputDevice() == device
            && engine.inputNode.outputFormat(forBus: 0) == tapFormat
        if !lastStartWasReady { try setUp() }
        buffer?.reset()
        do {
            try engine.start()
        } catch {
            tearDown()
            throw error
        }
        isRecording = true
    }

    /// Loudness of the most recent audio, in dBFS (`SilenceTrimmer.silentDecibels` when not recording).
    public var currentDecibels: Float {
        isRecording ? buffer?.latestDecibels ?? SilenceTrimmer.silentDecibels : SilenceTrimmer.silentDecibels
    }

    public func stop() async -> AudioClip {
        engine.pause()  // the hardware stops; the setup stays for the next recording
        isRecording = false
        let samples = buffer?.allSamples() ?? []
        return trimmer.trim(AudioClip(samples: samples, sampleRate: Self.sampleRate))
    }

    public func takeAudio() -> [Float] {
        buffer?.takeNew() ?? []
    }

    /// Installs the tap for the current input and prepares the engine, without starting it.
    private func setUp() throws {
        tearDown()
        let current = Self.defaultInputDevice()
        if device != nil, current != device {
            // Another microphone is now the default: a new engine picks it up.
            engine = AVAudioEngine()
            observe(engine)
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw MicRecorderError.noInputDevice }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false)
        else { throw MicRecorderError.unsupportedFormat }
        let buffer = buffer ?? ConvertingBuffer(to: targetFormat, onAppend: Self.announcer(for: self))
        guard buffer.use(inputFormat: inputFormat) else { throw MicRecorderError.unsupportedFormat }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: Self.tapBlock(appendingTo: buffer))
        engine.prepare()
        self.buffer = buffer
        tapFormat = inputFormat
        device = current
    }

    private func tearDown() {
        guard tapFormat != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tapFormat = nil
    }

    private func inputChanged() {
        do {
            try setUp()
            if isRecording { try engine.start() }  // carry on recording from the new input
            onNote?("Mic: input changed; set up again\(isRecording ? " mid-recording" : "")")
        } catch {
            // The audio so far is kept; the next recording tries again.
            if isRecording { onNote?("Mic: input changed mid-recording and couldn't be set up again (\(error)); the rest of this recording is lost") }
            isRecording = false
        }
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }
}

extension MicRecorder {
    // Both built outside the main actor: they run on the audio render thread, and a closure formed in a
    // @MainActor method would inherit that isolation and trap at runtime.

    /// Called after each tapped buffer (~85 ms): tells `onAudio` on the main queue, in order.
    nonisolated private static func announcer(for recorder: MicRecorder) -> @Sendable () -> Void {
        { [weak recorder] in
            DispatchQueue.main.async { MainActor.assumeIsolated { recorder?.onAudio?() } }
        }
    }

    nonisolated private static func tapBlock(appendingTo buffer: ConvertingBuffer) -> AVAudioNodeTapBlock {
        { pcm, when in buffer.append(pcm, capturedAt: when.isHostTimeValid ? when.hostTime : nil) }
    }
}

public enum MicRecorderError: Error {
    case noInputDevice
    case unsupportedFormat
}

/// Converts tapped buffers to the target format and accumulates one recording's samples.
/// Appended from the audio render thread, read on the main actor.
private final class ConvertingBuffer: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let onAppend: @Sendable () -> Void
    private let lock = NSLock()
    private var samples: [Float] = []
    /// How many samples `takeNew()` has handed out.
    private var taken = 0
    /// Host time of the first sample recorded.
    private var firstHostTime: UInt64?
    private var decibels: Float = SilenceTrimmer.silentDecibels

    init(to target: AVAudioFormat, onAppend: @escaping @Sendable () -> Void) {
        self.targetFormat = target
        self.onAppend = onAppend
    }

    /// Takes audio in `inputFormat` (the input device's) from now on. False if it can't be converted.
    func use(inputFormat: AVAudioFormat) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        return converter != nil
    }

    /// Starts a new recording: drops the last one's audio and whatever the converter still held of it.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples = []
        taken = 0
        firstHostTime = nil
        decibels = SilenceTrimmer.silentDecibels
        converter?.reset()
    }

    var firstCaptured: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return firstHostTime
    }

    func append(_ pcm: AVAudioPCMBuffer, capturedAt hostTime: UInt64?) {
        let ratio = targetFormat.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        lock.lock()
        defer { lock.unlock() }
        // A late buffer from the previous input's format is dropped rather than misconverted.
        guard let converter, pcm.format == converter.inputFormat else { return }
        if firstHostTime == nil { firstHostTime = hostTime }
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
