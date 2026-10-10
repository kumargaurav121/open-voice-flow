import Core
import Foundation

extension CloudLLM.Service {
    public var displayName: String { keyAccount.displayName }

    /// Fast, cheap models suited to "only fix punctuation"; the user can name another in Settings.
    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .groq: "qwen/qwen3.8-27b"
        }
    }

    var chatCompletions: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .groq: URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        }
    }

    nonisolated public var keyAccount: APIKeys.Account {
        switch self {
        case .openAI: .openAI
        case .groq: .groq
        }
    }
}

/// AI cleanup by a cloud LLM over the OpenAI chat-completions API (OpenAI or Groq), with the same
/// instructions as the local model; its output still has to pass `AICleanupGuard`. The text leaves the
/// Mac, so this runs only when AI Cleanup is set to Cloud.
@MainActor
public final class OpenAICompatibleCleaner: TextCleaner {
    private let llm: () -> CloudLLM
    private let apiKey: (CloudLLM.Service) throws -> String?
    private let vocabulary: () -> [String]
    private let session: URLSession

    public init(llm: @escaping () -> CloudLLM, apiKey: @escaping (CloudLLM.Service) throws -> String?,
                vocabulary: @escaping () -> [String] = { [] }, session: URLSession = CloudRequest.session) {
        self.llm = llm
        self.apiKey = apiKey
        self.vocabulary = vocabulary
        self.session = session
    }

    public func clean(_ text: String) async throws -> String {
        let llm = llm()
        let service = llm.service
        guard let key = try apiKey(service) else { throw CloudError.missingKey(service.displayName) }
        var request = URLRequest(url: service.chatCompletions, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let model = llm.resolvedModel
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            // Deterministic with the default models; a model the user named might refuse a temperature.
            temperature: model == service.defaultModel ? 0 : nil,
            messages: [
                .init(role: "system", content: CleanupPrompt.instructions(vocabulary: vocabulary())),
                .init(role: "user", content: text),
            ]
        ))

        let data = try await CloudRequest.send(request, to: service.displayName, with: session) { body in
            (try? JSONDecoder().decode(ChatError.self, from: body))?.error.message
        }
        guard let content = (try? JSONDecoder().decode(ChatReply.self, from: data))?.choices.first?.message.content else {
            throw CloudError.unexpectedReply(service.displayName)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let temperature: Double?
    let messages: [Message]
}

private struct ChatReply: Decodable {
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String? }
    let choices: [Choice]
}

private struct ChatError: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

extension CloudLLM {
    /// The model to ask for: the one the user named, or the service's default.
    public var resolvedModel: String {
        let named = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return named.isEmpty ? service.defaultModel : named
    }
}
