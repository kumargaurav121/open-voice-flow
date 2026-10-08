import Foundation
import OSLog

/// Writes to the unified log (notice level, so it persists) and to
/// ~/Library/Logs/OpenVoiceFlow/OpenVoiceFlow.log, which Console.app also shows.
struct AppLog {
    private let logger = Logger(subsystem: "dev.openvoiceflow.OpenVoiceFlow", category: "session")
    private let file = URL.libraryDirectory.appending(path: "Logs/OpenVoiceFlow/OpenVoiceFlow.log")

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        append("\(message)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR \(message)")
    }

    private func append(_ line: String) {
        let stamped = "\(Date.now.formatted(.iso8601)) \(line)\n"
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(stamped.utf8))
            } else {
                try Data(stamped.utf8).write(to: file)
            }
        } catch {
            logger.error("Couldn't write log file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
