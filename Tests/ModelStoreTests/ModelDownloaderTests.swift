import CryptoKit
import Foundation
import Testing
@testable import ModelStore

/// Serves files from memory; can stop partway to simulate a dropped connection.
final class FakeTransport: Transport, @unchecked Sendable {
    var files: [String: Data] = [:]
    /// Deliver at most this many bytes per request, then fail (nil = whole file).
    var dropAfter: Int?
    private(set) var requests: [(path: String, offset: Int)] = []

    func download(_ url: URL, appendingTo destination: URL, from offset: Int, progress: @escaping @Sendable (Int) -> Void) async throws {
        let path = url.pathComponents.last!
        requests.append((path, offset))
        guard let data = files[path] else { throw URLError(.fileDoesNotExist) }
        var chunk = data[offset...]
        var dropped = false
        if let dropAfter, chunk.count > dropAfter {
            chunk = chunk.prefix(dropAfter)
            dropped = true
        }
        if !FileManager.default.fileExists(atPath: destination.path) { FileManager.default.createFile(atPath: destination.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: destination)
        try handle.seekToEnd()
        try handle.write(contentsOf: chunk)
        try handle.close()
        progress(chunk.count)
        if dropped { throw URLError(.networkConnectionLost) }
    }
}

struct ModelDownloaderTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ovf-models-\(UUID().uuidString)")
    let weights = Data((0..<5_000).map { UInt8($0 % 251) })
    let config = Data(#"{"model_type":"whisper"}"#.utf8)

    func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func manifest(weightsHash: String? = nil) -> ModelManifest {
        ModelManifest(id: "test", folderName: "test-model", repo: "org/test", revision: String(repeating: "a", count: 40), license: "MIT", files: [
            .init(path: "config.json", size: config.count, sha256: sha256(config)),
            .init(path: "weights.bin", size: weights.count, sha256: weightsHash ?? sha256(weights)),
        ])
    }

    func transport() -> FakeTransport {
        let fake = FakeTransport()
        fake.files = ["config.json": config, "weights.bin": weights]
        return fake
    }

    @Test func downloadsVerifiesAndInstallsEveryFile() async throws {
        let store = ModelDownloader(root: root, transport: transport())

        try await store.install(manifest()) { _ in }

        let folder = root.appending(path: "test-model")
        #expect(try Data(contentsOf: folder.appending(path: "weights.bin")) == weights)
        #expect(try Data(contentsOf: folder.appending(path: "config.json")) == config)
        #expect(store.isInstalled(manifest()))
    }

    @Test func aDroppedDownloadResumesWhereItStopped() async throws {
        let fake = transport()
        fake.dropAfter = 2_000
        let store = ModelDownloader(root: root, transport: fake)

        await #expect(throws: URLError.self) { try await store.install(manifest()) { _ in } }
        #expect(!store.isInstalled(manifest()))

        fake.dropAfter = nil
        try await store.install(manifest()) { _ in }

        #expect(fake.requests.filter { $0.path == "weights.bin" }.map(\.offset) == [0, 2_000])
        #expect(try Data(contentsOf: root.appending(path: "test-model/weights.bin")) == weights)
        #expect(store.isInstalled(manifest()))
    }

    @Test func aChecksumMismatchDeletesTheWholeDownloadAndInstallsNothing() async throws {
        let store = ModelDownloader(root: root, transport: transport())
        let tampered = manifest(weightsHash: String(repeating: "0", count: 64))

        await #expect(throws: ModelDownloader.ChecksumMismatch.self) { try await store.install(tampered) { _ in } }

        #expect(!store.isInstalled(tampered))
        // config.json had verified, but nothing from a source that served a bad file is kept.
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "test-model").path))
    }

    @Test func anInstalledModelRecordsWhereItCameFrom() async throws {
        let store = ModelDownloader(root: root, transport: transport())

        try await store.install(manifest()) { _ in }

        let folder = root.appending(path: "test-model")
        let attribution = try String(contentsOf: folder.appending(path: "ATTRIBUTION.md"), encoding: .utf8)
        #expect(attribution.contains("org/test at revision \(String(repeating: "a", count: 40))"))
        #expect(attribution.contains("licensed MIT"))
        let sums = try String(contentsOf: folder.appending(path: "SOURCE-SHA256SUMS"), encoding: .utf8)
        #expect(sums == "\(sha256(config))  config.json\n\(sha256(weights))  weights.bin\n")
    }

    @Test func progressCountsOnlyNetworkBytesAsFetched() async throws {
        let fake = transport()
        let store = ModelDownloader(root: root, transport: fake)
        try await store.install(manifest()) { _ in }
        var second = manifest()
        second.revision = String(repeating: "b", count: 40)  // same files on disk, re-verified, not fetched
        let recorder = ProgressRecorder()

        try await store.install(second) { recorder.record($0) }

        #expect(recorder.last?.downloaded == config.count + weights.count)
        #expect(recorder.last?.fetched == 0)
    }

    @Test func progressAddsUpToTheModelsSize() async throws {
        let store = ModelDownloader(root: root, transport: transport())
        let recorder = ProgressRecorder()

        try await store.install(manifest()) { recorder.record($0) }

        #expect(recorder.last?.downloaded == config.count + weights.count)
        #expect(recorder.last?.total == config.count + weights.count)
    }

    @Test func installingSeveralModelsReportsOneRunningTotal() async throws {
        let store = ModelDownloader(root: root, transport: transport())
        var second = manifest()
        second.folderName = "second-model"
        let recorder = ProgressRecorder()
        let size = config.count + weights.count

        try await store.installAll([manifest(), second]) { recorder.record($0) }

        #expect(recorder.all.allSatisfy { $0.total == 2 * size })
        #expect(recorder.all.map(\.downloaded) == recorder.all.map(\.downloaded).sorted())
        #expect(recorder.last?.downloaded == 2 * size)
        #expect(store.isInstalled(manifest()) && store.isInstalled(second))
    }

    @Test func anInstalledModelIsNotDownloadedAgain() async throws {
        let fake = transport()
        let store = ModelDownloader(root: root, transport: fake)
        try await store.install(manifest()) { _ in }
        let requestsAfterFirst = fake.requests.count

        try await store.install(manifest()) { _ in }

        #expect(fake.requests.count == requestsAfterFirst)
    }

    @Test func aDifferentRevisionCountsAsNotInstalled() async throws {
        let store = ModelDownloader(root: root, transport: transport())
        try await store.install(manifest()) { _ in }

        var newer = manifest()
        newer.revision = String(repeating: "b", count: 40)

        #expect(!store.isInstalled(newer))
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private(set) var all: [DownloadProgress] = []
    var last: DownloadProgress? { all.last }
    func record(_ progress: DownloadProgress) { all.append(progress) }
}
