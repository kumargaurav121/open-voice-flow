import Foundation

/// Downloads over HTTPS, resuming with an HTTP `Range` request and writing each chunk to disk as it
/// arrives.
public final class URLSessionTransport: Transport {
    public struct HTTPError: LocalizedError {
        public let status: Int
        public let file: String
        public var errorDescription: String? { "Hugging Face answered HTTP \(status) for \(file)" }
    }

    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
    }

    public func download(_ url: URL, appendingTo destination: URL, from offset: Int, progress: @escaping @Sendable (Int) -> Void) async throws {
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }

        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let writer = ChunkWriter(file: file, offset: offset, fileName: url.lastPathComponent, progress: progress)
        let session = URLSession(configuration: configuration, delegate: writer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                writer.finished = { continuation.resume(with: $0) }
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

/// Session delegate for one download: checks the status, then appends each chunk to the file.
/// URLSession calls it on its own serial delegate queue.
private final class ChunkWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var finished: (Result<Void, Error>) -> Void = { _ in }
    private let file: FileHandle
    private let offset: Int
    private let fileName: String
    private let progress: @Sendable (Int) -> Void
    private var failure: Error?

    init(file: FileHandle, offset: Int, fileName: String, progress: @escaping @Sendable (Int) -> Void) {
        self.file = file
        self.offset = offset
        self.fileName = fileName
        self.progress = progress
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        do {
            let status = (response as? HTTPURLResponse)?.statusCode
            switch status {
            case 206:
                try file.seekToEnd()
            case 200:
                // The server ignored the range: start the file over.
                try file.truncate(atOffset: 0)
                if offset > 0 { progress(-offset) }
            case let status?:
                throw URLSessionTransport.HTTPError(status: status, file: fileName)
            case nil:
                throw URLError(.badServerResponse)
            }
            return .allow
        } catch {
            failure = error
            return .cancel
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try file.write(contentsOf: data)
            progress(data.count)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = failure ?? error {
            finished(.failure(error))
        } else {
            finished(.success(()))
        }
    }
}
