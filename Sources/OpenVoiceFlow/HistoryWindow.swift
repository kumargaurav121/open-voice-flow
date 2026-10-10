import AppKit
import Core
import History
import SwiftUI

/// The app's history: records each dictation and feeds the window, which reloads while it's open.
@MainActor
@Observable
final class HistoryModel {
    var query = "" { didSet { reload() } }
    private(set) var entries: [HistoryEntry] = []
    private(set) var error: String?
    /// Off unless the user turns it on.
    var keepAudio: Bool { didSet { UserDefaults.standard.set(keepAudio, forKey: Self.keepAudioKey) } }
    /// Set by the window; nothing is queried for it while it's closed.
    var isShowing = false

    static let keepAudioKey = "keepAudio"
    @ObservationIgnored private let store: HistoryStore?

    init(store: HistoryStore?) {
        self.store = store
        keepAudio = UserDefaults.standard.bool(forKey: Self.keepAudioKey)
        error = store == nil ? "History couldn't be opened." : nil
    }

    func record(_ transcript: SessionTranscript) throws {
        guard let store else { throw HistoryStore.Failure(message: "not available") }
        try store.save(transcript, at: .now, keepAudio: keepAudio)
        if isShowing { reload() }
    }

    func recent(_ count: Int) throws -> [HistoryEntry] {
        guard let store else { throw HistoryStore.Failure(message: "not available") }
        return try store.entries(limit: count)
    }

    func reload() {
        guard let store else { return }
        do {
            entries = try store.entries(matching: query.trimmingCharacters(in: .whitespaces))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ entry: HistoryEntry) {
        perform { try $0.delete(entry) }
    }

    func clear() {
        perform { try $0.clear() }
    }

    private func perform(_ change: (HistoryStore) throws -> Void) {
        guard let store else { return }
        do {
            try change(store)
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

}

@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Menu bar → History…: saved dictations (the newest 500; search covers all), with copy, delete and
/// Clear History.
@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    let model: HistoryModel
    private var window: NSWindow?

    init(model: HistoryModel) {
        self.model = model
    }

    func show() {
        model.isShowing = true
        model.reload()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "History"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(model: model))
            window.contentMinSize = NSSize(width: 400, height: 360)
            window.setFrameAutosaveName("History")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.isShowing = false
    }
}

private struct HistoryView: View {
    @Bindable var model: HistoryModel
    @State private var confirmingClear = false
    @State private var copied: HistoryEntry.ID?
    @State private var copiedReset: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.entries) { entry in
                    HistoryRow(entry: entry, copied: copied == entry.id) { copy(entry) }
                        .contextMenu {
                            Button("Copy") { copy(entry) }
                            if let audio = entry.audio {
                                Button("Show Recording in Finder") { NSWorkspace.shared.activateFileViewerSelecting([audio]) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { model.delete(entry) }
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay { emptyState }
            .searchable(text: $model.query, placement: .toolbar, prompt: "Search dictations")

            Divider()
            HStack {
                Text(model.keepAudio ? "Recordings are kept (Settings → Privacy)" : "Text only; recordings aren't kept")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History…") { confirmingClear = true }
                    .disabled(model.entries.isEmpty && model.query.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 400, minHeight: 360)
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { model.clear() }
        } message: {
            Text("Deletes every saved dictation and recording from this Mac. This can't be undone.")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let error = model.error {
            ContentUnavailableView("Couldn't Load History", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.entries.isEmpty {
            if model.query.isEmpty {
                ContentUnavailableView("No Dictations Yet", systemImage: "clock",
                                       description: Text("Everything you dictate is kept here, on this Mac only."))
            } else {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    private func copy(_ entry: HistoryEntry) {
        Clipboard.copy(entry.text)
        copied = entry.id
        // A new copy restarts the ✓'s timer rather than racing the old one.
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copied = nil }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .textSelection(.enabled)
                    .lineLimit(4)
                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    if let app = entry.app { Text("·"); Text(app) }
                    Text("·")
                    Text(entry.language.displayName)
                    if !entry.inserted {
                        Label("Not inserted", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                    if entry.audio != nil {
                        Image(systemName: "waveform").help("Recording kept")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .accessibilityLabel(copied ? "Copied" : "Copy")
        }
        .padding(.vertical, 4)
    }
}
