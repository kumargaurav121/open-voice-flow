import Foundation

/// One clip's result, in the shape scripts/eval (`ovf-eval score`) reads.
struct TranscriptRecord: Codable, Equatable {
    var id: Int
    var text: String
    var seconds: Double
}

enum TranscriptsFile {
    static func encode(_ records: [TranscriptRecord]) throws -> Data {
        let rounded = records.map { TranscriptRecord(id: $0.id, text: $0.text, seconds: ($0.seconds * 1000).rounded() / 1000) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(rounded)
    }
}
