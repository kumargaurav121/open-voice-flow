import Core
import Foundation
import Testing
@testable import Cloud

/// Records each request and answers with a canned status and body.
final class StubAPI: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data)] = []

    static func reset(status: Int = 200, json: String) {
        self.status = status
        body = Data(json.utf8)
        requests = []
    }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubAPI.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        Self.requests.append((request, body))
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized) struct CloudClientTests {
    let clip = AudioClip(samples: Array(repeating: 0.1, count: 1_600), sampleRate: 16_000)

    // MARK: Deepgram

    func deepgram(key: String? = "dg-secret", terms: [String] = []) -> DeepgramSpeechToText {
        DeepgramSpeechToText(apiKey: { key }, keyterms: { terms }, session: StubAPI.session)
    }

    @Test func deepgramGetsTheAudioWithTheKeyInTheHeaderOnly() async throws {
        StubAPI.reset(json: #"{"results":{"channels":[{"alternatives":[{"transcript":"Gurjeet ko message karo"}]}]}}"#)

        let text = try await deepgram(terms: ["Gurjeet", "Supabase"]).transcribe(clip, language: .hinglish)

        #expect(text == "Gurjeet ko message karo")
        let (request, body) = try #require(StubAPI.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token dg-secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "audio/wav")
        #expect(body == clip.wavData)
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://api.deepgram.com/v1/listen?"))
        #expect(!url.contains("dg-secret"))
        let query = Dictionary(uniqueKeysWithValues: URLComponents(string: url)!.queryItems!.filter { $0.name != "keyterm" }.map { ($0.name, $0.value!) })
        #expect(query["model"] == "nova-3")
        #expect(query["language"] == "multi")  // Hindi–English code-switching
        #expect(URLComponents(string: url)!.queryItems!.filter { $0.name == "keyterm" }.map(\.value) == ["Gurjeet", "Supabase"])
    }

    @Test func aLongDictionarySendsOnlyAsManyTermsAsDeepgramTakes() async throws {
        StubAPI.reset(json: #"{"results":{"channels":[{"alternatives":[{"transcript":"ok"}]}]}}"#)

        _ = try await deepgram(terms: (1...80).map { "Term\($0)" }).transcribe(clip, language: .english)

        let terms = URLComponents(url: StubAPI.requests[0].request.url!, resolvingAgainstBaseURL: false)!.queryItems!.filter { $0.name == "keyterm" }
        #expect(terms.count == DeepgramSpeechToText.maxKeyterms)
        #expect(terms.first?.value == "Term1")
    }

    @Test func englishModeAsksForEnglish() async throws {
        StubAPI.reset(json: #"{"results":{"channels":[{"alternatives":[{"transcript":"Hello"}]}]}}"#)

        _ = try await deepgram().transcribe(clip, language: .english)

        let items = URLComponents(url: StubAPI.requests[0].request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.contains(URLQueryItem(name: "language", value: "en")))
    }

    @Test func withoutAKeyNothingIsSent() async {
        StubAPI.reset(json: "{}")

        await #expect(throws: CloudError.missingKey("Deepgram")) {
            try await deepgram(key: nil).transcribe(clip, language: .english)
        }
        #expect(StubAPI.requests.isEmpty)
    }

    @Test func aRejectedRequestSaysWhyWithoutTheKey() async {
        StubAPI.reset(status: 401, json: #"{"err_code":"INVALID_AUTH","err_msg":"Invalid credentials."}"#)

        let error = await #expect(throws: CloudError.self) { try await deepgram().transcribe(clip, language: .english) }

        #expect(error?.localizedDescription == "Deepgram answered HTTP 401: Invalid credentials.")
        #expect(error?.localizedDescription.contains("dg-secret") == false)
    }

    // MARK: OpenAI-compatible cleanup

    func cleaner(_ service: CloudLLM.Service, model: String? = nil, key: String? = "sk-secret") -> OpenAICompatibleCleaner {
        OpenAICompatibleCleaner(llm: { CloudLLM(service: service, model: model) }, apiKey: { _ in key },
                                vocabulary: { ["Gurjeet"] }, session: StubAPI.session)
    }

    @Test func cleanupSendsTheSharedInstructionsToTheChosenService() async throws {
        StubAPI.reset(json: #"{"choices":[{"message":{"role":"assistant","content":"Message Gurjeet, I'm late."}}]}"#)

        let cleaned = try await cleaner(.groq).clean("message gurjeet im late")

        #expect(cleaned == "Message Gurjeet, I'm late.")
        let (request, body) = try #require(StubAPI.requests.first)
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-secret")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == CloudLLM.Service.groq.defaultModel)
        #expect(json["temperature"] as? Double == 0)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [
            ["role": "system", "content": CleanupPrompt.instructions(vocabulary: ["Gurjeet"])],
            ["role": "user", "content": "message gurjeet im late"],
        ])
    }

    @Test func openAIUsesItsOwnEndpointAndTheChosenModel() async throws {
        StubAPI.reset(json: #"{"choices":[{"message":{"content":"Hi."}}]}"#)

        _ = try await cleaner(.openAI, model: "gpt-4.1-mini").clean("hi")

        #expect(StubAPI.requests[0].request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        let json = try #require(try JSONSerialization.jsonObject(with: StubAPI.requests[0].body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-4.1-mini")
    }

    @Test func aModelTheUserNamedGetsNoTemperature() async throws {
        // Some models (e.g. OpenAI's reasoning models) refuse a temperature; the defaults are known to take 0.
        StubAPI.reset(json: #"{"choices":[{"message":{"content":"Hi."}}]}"#)

        _ = try await cleaner(.openAI, model: "o4-mini").clean("hi")

        let json = try #require(try JSONSerialization.jsonObject(with: StubAPI.requests[0].body) as? [String: Any])
        #expect(json["temperature"] == nil)
    }

    @Test func cleanupWithoutAKeySendsNothing() async {
        StubAPI.reset(json: "{}")

        await #expect(throws: CloudError.missingKey("Groq")) { try await cleaner(.groq, key: nil).clean("hi") }
        #expect(StubAPI.requests.isEmpty)
    }

    @Test func aFailedCleanupSaysWhy() async {
        StubAPI.reset(status: 429, json: #"{"error":{"message":"Rate limit reached","type":"rate_limit"}}"#)

        let error = await #expect(throws: CloudError.self) { try await cleaner(.openAI).clean("hi") }

        #expect(error?.localizedDescription == "OpenAI answered HTTP 429: Rate limit reached")
    }
}
