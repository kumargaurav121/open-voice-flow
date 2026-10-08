import Foundation
import MLXLMCommon
import Tokenizers

/// Loads a model folder's tokenizer with swift-transformers, the version WhisperKit already pins (1.1.x),
/// instead of mlx-swift-lm's MLXHuggingFace glue, which needs 1.3+ and conflicts with WhisperKit.
struct HuggingFaceTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        HuggingFaceTokenizer(try await AutoTokenizer.from(modelFolder: directory))
    }
}

/// swift-transformers 1.1 tokenizers aren't declared Sendable and may cache internally (BPE), so every
/// call goes through one lock; MLX may call from its own tasks.
struct HuggingFaceTokenizer: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let base: any Tokenizers.Tokenizer
    private let lock = NSLock()

    init(_ base: any Tokenizers.Tokenizer) {
        self.base = base
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] { locked { base.encode(text: text, addSpecialTokens: addSpecialTokens) } }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { locked { base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) } }
    func convertTokenToId(_ token: String) -> Int? { locked { base.convertTokenToId(token) } }
    func convertIdToToken(_ id: Int) -> String? { locked { base.convertIdToToken(id) } }
    var bosToken: String? { locked { base.bosToken } }
    var eosToken: String? { locked { base.eosToken } }
    var unknownToken: String? { locked { base.unknownToken } }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try locked { try base.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext) }
    }
}
