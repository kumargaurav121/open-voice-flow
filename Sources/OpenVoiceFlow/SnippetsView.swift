import AppKit
import Core
import SwiftUI

/// The Snippets tab in Settings: say a cue on its own, and its text is pasted exactly as saved.
struct SnippetsView: View {
    let store: SnippetStore
    /// The snippet being edited below the list; nil while writing a new one.
    @State private var selection: Snippet.ID?
    @State private var cue = ""
    @State private var text = ""
    @FocusState private var cueFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Say a cue on its own and its text is pasted exactly as saved, in any app. Undo Formatting (⌃⌥Z) puts back what you said.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.snippets) { snippet in
                        row(snippet)
                            .tag(snippet.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    if store.snippets.isEmpty {
                        ContentUnavailableView("No Snippets Yet", systemImage: "text.quote",
                                               description: Text("Add your address, a sign-off or a prompt you use often."))
                    }
                }
                .onDeleteCommand { removeSelected() }

                Divider()
                HStack(spacing: 0) {
                    Button { startNew() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help("Add a snippet")
                    Divider().frame(height: 16)
                    Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                        .help("Remove the selected snippet")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            editor
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 320)
        .onAppear { cueFocused = true }
        .onChange(of: selection) { old, new in
            keepEdits(of: old)
            load(new)
        }
    }

    @ViewBuilder private func row(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.cue)
            Text(snippet.text.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Remove", role: .destructive) { remove(snippet.id) }
        }
    }

    /// The new snippet, or the selected one: its cue, and its text, which scrolls past four lines.
    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Cue:")
                        .gridColumnAlignment(.trailing)
                    TextField("What you say, e.g. my address", text: $cue)
                        .textFieldStyle(.roundedBorder)
                        .focused($cueFocused)
                        .onSubmit { if canSave { save() } }
                }
                GridRow(alignment: .top) {
                    Text("Text:")
                        .padding(.top, 4)
                    PlainTextEditor(text: $text)
                        .frame(height: 76)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                }
            }
            HStack {
                if selection != nil {
                    Button("New Snippet", action: startNew)
                }
                Button(selection == nil ? "Add" : "Save", action: save)
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        guard SnippetStore.normalizedCue(cue) != nil, SnippetStore.normalizedText(text) != nil else { return false }
        guard let selected = store.snippets.first(where: { $0.id == selection }) else { return true }
        return selected.cue != cue || selected.text != text
    }

    private func load(_ id: Snippet.ID?) {
        let snippet = store.snippets.first { $0.id == id }
        cue = snippet?.cue ?? ""
        text = snippet?.text ?? ""
    }

    /// A new snippet: keeps a draft already under way (the selected one's edits are kept as it's left).
    private func startNew() {
        selection = nil
        cueFocused = true
    }

    /// Clicking away keeps an edit, like the Dictionary's (and Finder's rename): it's saved, or added if new, with a
    /// beep if it can't be (blank, or a cue already taken).
    private func keepEdits(of id: Snippet.ID?) {
        if let id {
            guard let saved = store.snippets.first(where: { $0.id == id }), saved.cue != cue || saved.text != text
            else { return }  // removed, or unchanged
            if !store.update(id, cue: cue, text: text) { NSSound.beep() }
        } else if !cue.isEmpty || !text.isEmpty, !store.add(cue: cue, text: text) {
            NSSound.beep()
        }
    }

    /// Adds the new snippet or saves the selected one; beeps if the cue is already another snippet's.
    private func save() {
        if let selection {
            if store.update(selection, cue: cue, text: text) { load(selection) } else { NSSound.beep() }
        } else if store.add(cue: cue, text: text) {
            load(nil)
            cueFocused = true
        } else {
            NSSound.beep()
        }
    }

    private func removeSelected() {
        if let selection { remove(selection) }
    }

    private func remove(_ id: Snippet.ID) {
        store.remove(id)
        if selection == id { startNew() }
    }
}

/// A multi-line text box that keeps exactly what's typed: no smart quotes, dashes or text replacements, which would
/// change a snippet meant to paste as saved ("--flag", "it's").
private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView  // a scrollable text view's document is its text view
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textContainerInset = NSSize(width: 2, height: 4)
        view.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        if view.string != text { view.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}
