/// A text field's observable state: its character count and selection (UTF-16, as Accessibility reports).
struct FieldState: Equatable {
    var length: Int
    var selection: Range<Int>
}

/// The focused field as Undo Formatting reads it: its state, when it can be read (never for a password field),
/// and what was found, for the log (its role, or why there's none; never the text).
struct FieldReading: Equatable {
    var diagnostic: String
    var state: FieldState?
}

/// What happened when we tried to type straight into the focused field via Accessibility.
enum DirectInsertResult: Equatable {
    /// No focused text field, or it refused the insert.
    case refused(diagnostic: String)
    /// The field accepted the call; its state before and after, where readable.
    case attempted(before: FieldState?, after: FieldState?, diagnostic: String)

    /// What we saw, for the session log (role and lengths, never the text).
    var diagnostic: String {
        switch self {
        case .refused(let diagnostic), .attempted(_, _, let diagnostic): diagnostic
        }
    }
}

/// Decides whether a direct insert really landed. Many apps (Electron, browsers) report success and do
/// nothing, so the field is checked: its length or cursor changed → done (an insert always moves the
/// cursor, even when it replaced a same-length selection); nothing changed or unreadable → paste instead.
enum InsertDecision {
    enum Verdict: Equatable {
        case inserted
        case fallBackToPaste
    }

    static func verdict(for result: DirectInsertResult) -> Verdict {
        guard case .attempted(let before?, let after?, _) = result, after != before else { return .fallBackToPaste }
        return .inserted
    }
}
