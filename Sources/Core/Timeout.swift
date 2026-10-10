import Foundation

/// An error that knows what's safe to write to the app log. A cloud provider's own message can echo part
/// of an API key or the transcript, so only this summary (or the error's type) is ever logged.
public protocol LogSafeError: Error {
    var logDescription: String { get }
}

/// What to log for an error: its safe summary, or just its type.
func logSafe(_ error: Error) -> String {
    (error as? LogSafeError)?.logDescription ?? String(describing: type(of: error))
}

struct TimedOut: Error {}

/// Returns the work's result, or throws `TimedOut` after `limit` even if the work ignores cancellation
/// (a model mid-generation may not check for it), or `CancellationError` when the caller is cancelled.
/// The work is cancelled either way.
@MainActor
func withTimeout<T: Sendable>(_ limit: Duration, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
    let race = Race<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.continuation = continuation
            race.worker = Task { @MainActor in
                let result: Result<T, Error>
                do { result = .success(try await work()) } catch { result = .failure(error) }
                race.finish(with: result)
            }
            race.timer = Task { @MainActor in
                guard (try? await Task.sleep(for: limit)) != nil else { return }  // cancelled: someone else won
                race.finish(with: .failure(TimedOut()))
            }
            if Task.isCancelled { race.finish(with: .failure(CancellationError())) }
        }
    } onCancel: {
        Task { @MainActor in race.finish(with: .failure(CancellationError())) }
    }
}

/// Resumes the continuation exactly once: whichever of the work, the timer and cancellation comes first
/// wins, and the others are cancelled.
@MainActor
private final class Race<T: Sendable> {
    var continuation: CheckedContinuation<T, Error>?
    var worker: Task<Void, Never>?
    var timer: Task<Void, Never>?

    func finish(with result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        worker?.cancel()
        timer?.cancel()
        continuation.resume(with: result)
    }
}

extension URLError: LogSafeError {
    public var logDescription: String { "network error \(code.rawValue)" }
}
