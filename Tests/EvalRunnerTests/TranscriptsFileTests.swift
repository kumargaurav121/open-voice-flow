import Foundation
import Testing
@testable import EvalRunner

struct TranscriptsFileTests {
    @Test func writesTheShapeOvfEvalReads() throws {
        let records = [
            TranscriptRecord(id: 9, text: "मैं आज देर से आऊंगा", seconds: 1.23456),
            TranscriptRecord(id: 21, text: "Hello", seconds: 0.5),
        ]

        let json = try JSONSerialization.jsonObject(with: TranscriptsFile.encode(records)) as? [[String: Any]]

        #expect(json?.count == 2)
        #expect(json?[0]["id"] as? Int == 9)
        #expect(json?[0]["text"] as? String == "मैं आज देर से आऊंगा")
        #expect(json?[0]["seconds"] as? Double == 1.235)
        #expect(Set(json?[0].keys ?? [:].keys) == ["id", "text", "seconds"])
    }

    @Test func keepsDevanagariReadableInTheFile() throws {
        let data = try TranscriptsFile.encode([TranscriptRecord(id: 1, text: "हैं", seconds: 1)])

        #expect(String(decoding: data, as: UTF8.self).contains("हैं"))
    }
}
