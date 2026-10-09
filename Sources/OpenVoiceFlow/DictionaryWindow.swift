import AppKit
import Core
import SwiftUI

/// Menu bar → Dictionary…: the list of names and terms to spell the user's way. Moves into Settings with
/// ticket 10.
@MainActor
final class DictionaryWindow {
    private let store: DictionaryStore
    private var window: NSWindow?

    init(store: DictionaryStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Dictionary"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DictionaryView(store: store))
            window.contentMinSize = NSSize(width: 340, height: 320)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DictionaryView: View {
    let store: DictionaryStore
    @State private var newTerm = ""
    @State private var selection: String?
    @State private var editing: String?
    @State private var draft = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case add, edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Names and words to spell your way. Anything that sounds like one of these is written exactly as you spell it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.terms, id: \.self) { term in
                        row(term)
                            .tag(term)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    if store.terms.isEmpty {
                        ContentUnavailableView("No Words Yet", systemImage: "character.book.closed",
                                               description: Text("Add names like Gurjeet or products like Supabase."))
                    }
                }
                .onDeleteCommand { removeSelected() }
                .onKeyPress(.return) {
                    guard editing == nil, let selection else { return .ignored }
                    startEditing(selection)
                    return .handled
                }

                Divider()
                HStack(spacing: 0) {
                    Button { focus = .add } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help("Add a word")
                    Divider().frame(height: 16)
                    Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                        .help("Remove the selected word")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                TextField("Add a word, e.g. Gurjeet", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .add)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(DictionaryStore.normalized(newTerm) == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 320)
        .onAppear { focus = .add }
        // Clicking away from a word being edited keeps the edit, like Finder's rename.
        .onChange(of: focus) { old, new in
            if old == .edit, new != .edit, let editing { commitEdit(editing) }
        }
    }

    @ViewBuilder private func row(_ term: String) -> some View {
        if editing == term {
            TextField("Word", text: $draft)
                .textFieldStyle(.plain)
                .focused($focus, equals: .edit)
                .onSubmit { commitEdit(term) }
                .onExitCommand { editing = nil }
        } else {
            Text(term)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Alongside the List's own click handling, so single clicks still select.
                .simultaneousGesture(TapGesture(count: 2).onEnded { startEditing(term) })
                .contextMenu {
                    Button("Edit") { startEditing(term) }
                    Button("Remove", role: .destructive) { remove(term) }
                }
        }
    }

    private func add() {
        if store.add(newTerm) {
            selection = store.terms.last
            newTerm = ""
        } else {
            NSSound.beep()  // blank or already in the list
        }
    }

    private func startEditing(_ term: String) {
        if let editing, editing != term { commitEdit(editing) }
        draft = term
        editing = term
        selection = term
        focus = .edit
    }

    /// Keeps the new spelling, or (if it's blank or a duplicate) beeps and keeps the old one.
    private func commitEdit(_ term: String) {
        editing = nil
        if draft != term, store.update(term, to: draft) {
            selection = DictionaryStore.normalized(draft)
        } else if draft != term {
            NSSound.beep()
        }
    }

    private func removeSelected() {
        if let selection { remove(selection) }
    }

    private func remove(_ term: String) {
        store.remove(term)
        if selection == term { selection = nil }
        if editing == term { editing = nil }
    }
}
