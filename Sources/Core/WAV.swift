import Foundation

extension AudioClip {
    /// 16-bit PCM mono WAV: the simplest format every player (and speech API) accepts.
    public var wavData: Data {
        let sampleRate = UInt32(self.sampleRate)
        let payload = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(payload))
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + payload)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                 // PCM, mono
        append(sampleRate); append(sampleRate * 2)            // byte rate
        append(UInt16(2)); append(UInt16(16))                 // block align, bits per sample
        data.append(contentsOf: Array("data".utf8)); append(payload)
        // One pass into a buffer (a minute of audio is ~1M samples); NaN becomes silence.
        let pcm = samples.map { $0.isNaN ? 0 : Int16(max(-1, min(1, $0)) * Float(Int16.max)).littleEndian }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
