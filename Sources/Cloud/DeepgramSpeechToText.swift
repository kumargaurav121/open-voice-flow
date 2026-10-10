import Core
import Foundation

/// Speech-to-text by Deepgram Nova-3 with the user's own key. The recording leaves the Mac, so this runs
/// only when the user picks Deepgram in Settings. Hinglish mode asks for Nova-3's multilingual
/// code-switching; the dictionary goes along as key terms (the first `maxKeyterms`).
@MainActor
public final class DeepgramSpeechToText: SpeechToText {
    static let endpoint = URL(string: "https://api.deepgram.com/v1/listen")!
    /// Deepgram caps key-term prompting (about 500 tokens); a few dozen names stay well inside it.
    public static let maxKeyterms = 50

    private let apiKey: () throws -> String?
    private let keyterms: () -> [String]
    private let session: URLSession

    public init(apiKey: @escaping () throws -> String?, keyterms: @escaping () -> [String] = { [] },
                session: URLSession = CloudRequest.session) {
        self.apiKey = apiKey
        self.keyterms = keyterms
        self.session = session
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        guard let key = try apiKey() else { throw CloudError.missingKey("Deepgram") }
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language == .english ? "en" : "multi"),
            URLQueryItem(name: "smart_format", value: "true"),
        ] + keyterms().prefix(Self.maxKeyterms).map { URLQueryItem(name: "keyterm", value: $0) }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = clip.wavData

        let data = try await CloudRequest.send(request, to: "Deepgram", with: session) { body in
            (try? JSONDecoder().decode(DeepgramError.self, from: body))?.err_msg
        }
        guard let reply = try? JSONDecoder().decode(DeepgramReply.self, from: data),
              let transcript = reply.results.channels.first?.alternatives.first?.transcript
        else { throw CloudError.unexpectedReply("Deepgram") }
        return transcript
    }
}

private struct DeepgramReply: Decodable {
    struct Results: Decodable { let channels: [Channel] }
    struct Channel: Decodable { let alternatives: [Alternative] }
    struct Alternative: Decodable { let transcript: String }
    let results: Results
}

private struct DeepgramError: Decodable {
    let err_msg: String?
}
