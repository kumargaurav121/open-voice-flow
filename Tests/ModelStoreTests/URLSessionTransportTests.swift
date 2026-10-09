import Foundation
import Testing
@testable import ModelStore

/// Answers requests from a canned body, honouring (or ignoring) the Range header like a real server.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status: Int?
    nonisolated(unsafe) static var honoursRange = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var status = Self.status ?? 200
        var payload = Self.body
        if Self.status == nil, Self.honoursRange, let range = request.value(forHTTPHeaderField: "Range"),
           let start = Int(range.dropFirst("bytes=".count).dropLast()) {
            status = 206
            payload = Self.body.subdata(in: start..<Self.body.count)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status < 400 {
            // In pieces, like a network would deliver it.
            stride(from: 0, to: payload.count, by: 1_000).forEach {
                client?.urlProtocol(self, didLoad: payload.subdata(in: $0..<min($0 + 1_000, payload.count)))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ByteTally: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0
    var total: Int { lock.withLock { bytes } }
    func add(_ count: Int) { lock.withLock { bytes += count } }
}

@Suite(.serialized) struct URLSessionTransportTests {
    let body = Data((0..<5_000).map { UInt8($0 % 251) })
    let url = URL(string: "https://huggingface.co/org/test/resolve/abc/weights.bin")!
    let file = FileManager.default.temporaryDirectory.appending(path: "ovf-transport-\(UUID().uuidString)")

    func transport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSessionTransport(configuration: configuration)
    }

    func reset() {
        StubServer.body = body
        StubServer.status = nil
        StubServer.honoursRange = true
    }

    @Test func resumesFromTheOffsetWithARangeRequest() async throws {
        reset()
        try body.prefix(2_000).write(to: file)
        let tally = ByteTally()

        try await transport().download(url, appendingTo: file, from: 2_000) { tally.add($0) }

        #expect(try Data(contentsOf: file) == body)
        #expect(tally.total == 3_000)
    }

    @Test func startsOverWhenTheServerIgnoresTheRange() async throws {
        reset()
        StubServer.honoursRange = false
        try body.prefix(2_000).write(to: file)
        let tally = ByteTally()

        try await transport().download(url, appendingTo: file, from: 2_000) { tally.add($0) }

        #expect(try Data(contentsOf: file) == body)
        // Takes back the 2,000 bytes it had counted, then counts the whole file.
        #expect(tally.total == 3_000)
    }

    @Test func anHTTPErrorSaysWhatFailed() async throws {
        reset()
        StubServer.status = 404

        let error = await #expect(throws: URLSessionTransport.HTTPError.self) {
            try await transport().download(url, appendingTo: file, from: 0) { _ in }
        }
        #expect(error?.localizedDescription == "Hugging Face answered HTTP 404 for weights.bin")
    }
}
