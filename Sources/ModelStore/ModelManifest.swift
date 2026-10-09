import Foundation

/// A model the app downloads: pinned Hugging Face repo + full commit SHA, and every file's size and
/// SHA-256 (ADR 0010). Built into the app, so a tampered or swapped upstream file fails verification.
public struct ModelManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public var path: String
        public var size: Int
        public var sha256: String

        public init(path: String, size: Int, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public var id: String
    /// Folder under the models directory.
    public var folderName: String
    public var repo: String
    public var revision: String
    /// Folder inside the repo the files live in (Argmax keeps one model per folder); "" for the root.
    public var subfolder: String
    public var license: String
    public var files: [File]

    public init(id: String, folderName: String, repo: String, revision: String, subfolder: String = "",
                license: String, files: [File]) {
        self.id = id
        self.folderName = folderName
        self.repo = repo
        self.revision = revision
        self.subfolder = subfolder
        self.license = license
        self.files = files
    }

    /// Where every model lives: the app's Application Support folder, never the app bundle.
    public static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "open-voice-flow/models", directoryHint: .isDirectory)
    }

    /// This model's installed folder under `modelsDirectory`.
    public var installedFolder: URL {
        Self.modelsDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    public var totalSize: Int { files.reduce(0) { $0 + $1.size } }

    func url(for file: File) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        let repoPath = subfolder.isEmpty ? file.path : "\(subfolder)/\(file.path)"
        components.path = "/\(repo)/resolve/\(revision)/\(repoPath)"
        return components.url!
    }
}

public struct DownloadProgress: Sendable, Equatable {
    /// Bytes done: downloaded, or already on disk and verified.
    public var downloaded: Int
    public var total: Int
    /// Of `downloaded`, the bytes that came over the network in this run (for a download-rate estimate).
    public var fetched: Int

    public init(downloaded: Int, total: Int, fetched: Int = 0) {
        self.downloaded = downloaded
        self.total = total
        self.fetched = fetched
    }

    public var fraction: Double { total == 0 ? 1 : Double(downloaded) / Double(total) }
}
