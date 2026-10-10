import Foundation

/// The speech-to-text provider the user picked, read per dictation so a change applies to the next one.
/// The cloud provider is only ever called when it's the choice; if it fails or takes longer than
/// `cloudTimeout` (no network, bad key, outage) the dictation is transcribed on this Mac instead, and the
/// reason logged. A cancelled dictation stays cancelled.
@MainActor
public final class SelectedSpeechToText: SpeechToText {
    private let local: SpeechToText
    private let cloud: SpeechToText
    private let provider: () -> SpeechProvider
    private let cloudTimeout: Duration
    private let log: (String) -> Void

    public init(local: SpeechToText, cloud: SpeechToText, provider: @escaping () -> SpeechProvider,
                cloudTimeout: Duration = .seconds(8), log: @escaping (String) -> Void) {
        self.local = local
        self.cloud = cloud
        self.provider = provider
        self.cloudTimeout = cloudTimeout
        self.log = log
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        guard provider() == .deepgram else { return try await local.transcribe(clip, language: language) }
        let cloud = cloud
        do {
            return try await withTimeout(cloudTimeout) { try await cloud.transcribe(clip, language: language) }
        } catch is CancellationError {
            throw CancellationError()
        } catch is TimedOut {
            log("Cloud speech-to-text timed out after \(cloudTimeout); used this Mac")
        } catch {
            log("Cloud speech-to-text failed (\(logSafe(error))); used this Mac")
        }
        try Task.checkCancellation()
        return try await local.transcribe(clip, language: language)
    }
}
