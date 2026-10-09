import CryptoKit
import Foundation

/// Fetches bytes over the network, appending to a partial file from an offset (HTTP Range). Reports each
/// chunk's byte count; a negative count means the server restarted the file from zero.
public protocol Transport: Sendable {
    func download(_ url: URL, appendingTo destination: URL, from offset: Int, progress: @escaping @Sendable (Int) -> Void) async throws
}

/// Installs models from their manifests: resumable downloads into `<file>.partial`, each file SHA-256
/// verified before it's moved into place, and a model only counts as installed once every file verified
/// and the revision marker is written. A checksum mismatch deletes the model's whole download.
public final class ModelDownloader: Sendable {
    public struct ChecksumMismatch: LocalizedError, Equatable {
        public let path: String
        public var errorDescription: String? { "\(path) didn't match its published checksum" }
    }

    static let markerName = ".installed-revision"
    /// "<sha256>  <path>" for each file verified so far, so a retry doesn't re-hash gigabytes.
    static let verifiedName = ".verified"

    private let root: URL
    private let transport: Transport

    public init(root: URL = ModelManifest.modelsDirectory, transport: Transport) {
        self.root = root
        self.transport = transport
    }

    public func folder(for manifest: ModelManifest) -> URL {
        root.appending(path: manifest.folderName, directoryHint: .isDirectory)
    }

    public func isInstalled(_ manifest: ModelManifest) -> Bool {
        let folder = folder(for: manifest)
        guard let marker = try? String(contentsOf: folder.appending(path: Self.markerName), encoding: .utf8),
              marker == manifest.revision
        else { return false }
        return manifest.files.allSatisfy { size(of: folder.appending(path: $0.path)) == $0.size }
    }

    public func install(_ manifest: ModelManifest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        try await installAll([manifest], progress: progress)
    }

    /// Installs each model in turn, reporting one running total across all of them.
    public func installAll(_ manifests: [ModelManifest], progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let counter = ByteCounter(total: manifests.reduce(0) { $0 + $1.totalSize }, report: progress)
        for manifest in manifests {
            if isInstalled(manifest) {
                counter.add(manifest.totalSize)
            } else {
                try await install(manifest, counting: counter)
            }
        }
    }

    private func install(_ manifest: ModelManifest, counting counter: ByteCounter) async throws {
        let folder = folder(for: manifest)
        try? FileManager.default.removeItem(at: folder.appending(path: Self.markerName))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var verified = readVerified(in: folder)

        for file in manifest.files {
            let final = folder.appending(path: file.path)
            try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            if size(of: final) == file.size {
                if verified[file.path] == file.sha256 {
                    counter.add(file.size)
                    continue
                }
                // On disk from before (an older install or a script): verify it once, keep it if it matches.
                if try await Self.sha256(of: final) == file.sha256 {
                    try markVerified(file, in: folder, into: &verified)
                    counter.add(file.size)
                    continue
                }
            }
            try? FileManager.default.removeItem(at: final)

            let partial = final.appendingPathExtension("partial")
            var offset = size(of: partial) ?? 0
            if offset > file.size {  // can't be ours; start over
                try FileManager.default.removeItem(at: partial)
                offset = 0
            }
            counter.add(offset)
            if offset < file.size {
                try await transport.download(manifest.url(for: file), appendingTo: partial, from: offset) { counter.add($0, fetched: true) }
            }
            guard try await Self.sha256(of: partial) == file.sha256 else {
                // The source can't be trusted any more: nothing from this download stays (ADR 0010).
                try? FileManager.default.removeItem(at: folder)
                throw ChecksumMismatch(path: file.path)
            }
            try FileManager.default.moveItem(at: partial, to: final)
            try markVerified(file, in: folder, into: &verified)
        }
        try writeProvenance(for: manifest, in: folder)
        try manifest.revision.write(to: folder.appending(path: Self.markerName), atomically: true, encoding: .utf8)
    }

    /// ATTRIBUTION.md and SOURCE-SHA256SUMS (ADR 0010), unless the model ships its own.
    private func writeProvenance(for manifest: ModelManifest, in folder: URL) throws {
        let shipped = Set(manifest.files.map(\.path))
        if !shipped.contains("ATTRIBUTION.md") {
            let source = manifest.subfolder.isEmpty ? manifest.repo : "\(manifest.repo) (\(manifest.subfolder))"
            let attribution = """
                \(source) at revision \(manifest.revision) (https://huggingface.co/\(manifest.repo)), \
                licensed \(manifest.license) by its authors.
                Downloaded unmodified by Open Voice Flow; every file verified against the SHA-256 pinned in the app \
                (checksums in SOURCE-SHA256SUMS).

                """
            try attribution.write(to: folder.appending(path: "ATTRIBUTION.md"), atomically: true, encoding: .utf8)
        }
        if !shipped.contains("SOURCE-SHA256SUMS") {
            let sums = manifest.files.map { "\($0.sha256)  \($0.path)\n" }.joined()
            try sums.write(to: folder.appending(path: "SOURCE-SHA256SUMS"), atomically: true, encoding: .utf8)
        }
    }

    private func readVerified(in folder: URL) -> [String: String] {
        let text = (try? String(contentsOf: folder.appending(path: Self.verifiedName), encoding: .utf8)) ?? ""
        var verified: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2 { verified[parts[1].trimmingCharacters(in: .whitespaces)] = String(parts[0]) }
        }
        return verified
    }

    private func markVerified(_ file: ModelManifest.File, in folder: URL, into verified: inout [String: String]) throws {
        verified[file.path] = file.sha256
        let text = verified.sorted { $0.key < $1.key }.map { "\($0.value)  \($0.key)\n" }.joined()
        try text.write(to: folder.appending(path: Self.verifiedName), atomically: true, encoding: .utf8)
    }

    private func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    /// Streams the file in 4 MB chunks on a utility queue, so hashing multi-GB weights neither sits in memory
    /// nor holds up Swift's cooperative threads.
    private static func sha256(of url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var hasher = SHA256()
                    while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                        hasher.update(data: chunk)
                    }
                    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
                })
            }
        }
    }
}

/// Totals bytes across files and reports the running progress.
private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var downloaded = 0
    private var fetched = 0
    private let total: Int
    private let report: @Sendable (DownloadProgress) -> Void

    init(total: Int, report: @escaping @Sendable (DownloadProgress) -> Void) {
        self.total = total
        self.report = report
    }

    func add(_ bytes: Int, fetched isNetwork: Bool = false) {
        lock.lock()
        downloaded += bytes
        if isNetwork { fetched += bytes }
        let progress = DownloadProgress(downloaded: downloaded, total: total, fetched: fetched)
        lock.unlock()
        report(progress)
    }
}
