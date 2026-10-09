import Foundation
import Testing
@testable import Insertion

@MainActor
final class FakePasteboard: Pasteboard {
    var items: [[String: Data]] = []
    private(set) var changeCount = 0

    func snapshot() -> [[String: Data]] { items }

    func replace(with items: [[String: Data]]) {
        self.items = items
        changeCount += 1
    }

    var refusesWrites = false

    func writeString(_ string: String) -> Bool {
        guard !refusesWrites else { return false }
        replace(with: [["public.utf8-plain-text": Data(string.utf8), "org.nspasteboard.TransientType": Data()]])
        return true
    }

    /// Simulates the user (or another app) copying something.
    func userCopies(_ string: String) { replace(with: [["public.utf8-plain-text": Data(string.utf8)]]) }
}

@MainActor
struct ClipboardRestoreTests {
    let image: [String: Data] = ["public.png": Data([0x89, 0x50, 0x4E, 0x47]), "public.tiff": Data([1, 2, 3])]
    let file: [String: Data] = ["public.file-url": Data("file:///tmp/report.pdf".utf8)]

    @Test func everyItemAndTypeComesBackAfterOurWrite() {
        let pasteboard = FakePasteboard()
        pasteboard.replace(with: [image, file])
        let saved = ClipboardSnapshot.take(from: pasteboard)

        _ = pasteboard.writeString("dictated text")
        let restored = saved.restore(to: pasteboard, ifUnchangedSince: pasteboard.changeCount)

        #expect(restored)
        #expect(pasteboard.items == [image, file])
    }

    @Test func somethingCopiedInTheMeantimeIsNotOverwritten() {
        let pasteboard = FakePasteboard()
        pasteboard.replace(with: [image])
        let saved = ClipboardSnapshot.take(from: pasteboard)
        _ = pasteboard.writeString("dictated text")
        let ourWrite = pasteboard.changeCount

        pasteboard.userCopies("something new")
        let restored = saved.restore(to: pasteboard, ifUnchangedSince: ourWrite)

        #expect(!restored)
        #expect(pasteboard.items == [["public.utf8-plain-text": Data("something new".utf8)]])
    }

    @Test func anEmptyClipboardIsRestoredAsEmpty() {
        let pasteboard = FakePasteboard()
        let saved = ClipboardSnapshot.take(from: pasteboard)

        _ = pasteboard.writeString("dictated text")
        _ = saved.restore(to: pasteboard, ifUnchangedSince: pasteboard.changeCount)

        #expect(pasteboard.items.isEmpty)
    }
}
