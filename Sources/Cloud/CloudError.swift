import Core
import Foundation

public enum CloudError: LocalizedError, LogSafeError, Equatable {
    /// No key saved for this service; nothing was sent.
    case missingKey(String)
    /// The service refused or failed; carries its own explanation (never the key).
    case http(service: String, status: Int, message: String)
    /// The reply wasn't what the service documents.
    case unexpectedReply(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let service): "No \(service) API key saved (Settings → Providers)"
        case .http(let service, let status, let message): "\(service) answered HTTP \(status)\(message.isEmpty ? "" : ": \(message)")"
        case .unexpectedReply(let service): "\(service) sent a reply Open Voice Flow couldn't read"
        }
    }

    /// For the app log: never the service's own message, which can echo part of the key.
    public var logDescription: String {
        switch self {
        case .missingKey(let service): "no \(service) key"
        case .http(let service, let status, _): "HTTP \(status) from \(service)"
        case .unexpectedReply(let service): "unreadable reply from \(service)"
        }
    }
}

public enum CloudRequest {
    /// No cookies, cache or stored credentials: requests carry keys and transcripts.
    public static let session = URLSession(configuration: .ephemeral)

    /// Sends a request and returns the body of a 2xx reply, or a `CloudError` with the service's own message.
    static func send(_ request: URLRequest, to service: String, with session: URLSession,
                     errorMessage: @Sendable (Data) -> String?) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CloudError.http(service: service, status: status, message: errorMessage(data) ?? "")
        }
        return data
    }
}
