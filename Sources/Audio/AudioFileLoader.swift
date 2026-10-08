import AVFoundation
import Core

public enum AudioFileLoader {
    public enum LoadError: Error, CustomStringConvertible {
        case wrongFormat(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .wrongFormat(let name): "\(name) must be 16 kHz mono"
            case .unreadable(let name): "couldn't read \(name)"
            }
        }
    }

    /// Reads a 16 kHz mono file as the clip the app's recorder would produce.
    public static func load(_ url: URL) throws -> AudioClip {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == AudioClip.speechSampleRate, file.processingFormat.channelCount == 1 else {
            throw LoadError.wrongFormat(url.lastPathComponent)
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        try file.read(into: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength))
        return AudioClip(samples: Array(samples), sampleRate: AudioClip.speechSampleRate)
    }
}
