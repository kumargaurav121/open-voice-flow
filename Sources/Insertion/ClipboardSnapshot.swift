import AppKit

/// The system clipboard, narrowed to what saving and restoring it needs.
@MainActor
protocol Pasteboard: AnyObject {
    /// Bumps on every write, by anyone.
    var changeCount: Int { get }
    /// Every item, as type identifier → data.
    func snapshot() -> [[String: Data]]
    func replace(with items: [[String: Data]])
    /// Writes our dictated text, marked transient so clipboard-history apps skip it. False if refused.
    func writeString(_ string: String) -> Bool
}

/// nspasteboard.org markers that clipboard managers and password managers honour.
enum PasteboardMarker {
    /// A secret (e.g. from a password manager) that should not be kept or recorded.
    static let concealed = "org.nspasteboard.ConcealedType"
    /// Temporary content that clipboard-history apps should not record.
    static let transient = "org.nspasteboard.TransientType"
}

/// The user's clipboard before we borrowed it for a paste.
struct ClipboardSnapshot {
    let items: [[String: Data]]

    @MainActor
    static func take(from pasteboard: Pasteboard) -> ClipboardSnapshot {
        ClipboardSnapshot(items: pasteboard.snapshot())
    }

    /// Puts the saved items back, unless something was copied after our write (`changeCount` moved):
    /// then the user's newer copy wins. A password manager's concealed clipboard is cleared instead of
    /// restored, so the secret isn't republished after its manager meant it to expire.
    /// Returns whether it touched the clipboard.
    @MainActor
    func restore(to pasteboard: Pasteboard, ifUnchangedSince ourWrite: Int) -> Bool {
        guard pasteboard.changeCount == ourWrite else { return false }
        let concealed = items.contains { $0[PasteboardMarker.concealed] != nil }
        pasteboard.replace(with: concealed ? [] : items)
        return true
    }
}

extension NSPasteboard: Pasteboard {
    /// Note: reading every type forces lazily provided data (big images, Office formats) to be produced,
    /// and file promises don't survive the round trip; both are rare for what people copy before dictating.
    func snapshot() -> [[String: Data]] {
        (pasteboardItems ?? []).compactMap { item in
            let entries = Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type.rawValue, $0) }
            })
            return entries.isEmpty ? nil : entries
        }
    }

    func replace(with items: [[String: Data]]) {
        clearContents()
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        if !restored.isEmpty { writeObjects(restored) }
    }

    func writeString(_ string: String) -> Bool {
        clearContents()
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardMarker.transient))
        return writeObjects([item])
    }
}
