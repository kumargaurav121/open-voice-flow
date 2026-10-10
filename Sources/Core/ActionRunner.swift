import Foundation

/// What an action's steps share as they run, e.g. the person the search step resolved, and the guard every
/// step calls before it touches the app.
@MainActor
public final class ActionContext {
    public var recipient: String?
    /// Set once the irreversible input (Return on Send) has been made: from then on it may have happened.
    public private(set) var committed = false
    var isStopped: () -> Bool = { false }

    public init() {}

    /// Throws if Esc was pressed or the step timed out: call before every key press, click or paste, so a
    /// stopped or timed-out step never acts afterwards.
    public func checkStopped() throws {
        if isStopped() || Task.isCancelled { throw CancellationError() }
    }

    /// The point of no return: checks for Esc one last time, then marks the action as (maybe) done. Call
    /// immediately before the irreversible input.
    public func commit() throws {
        try checkStopped()
        committed = true
    }
}

/// One visible step of an action (activate Slack, search, open the DM, …).
public struct ActionStep: Sendable {
    public let title: String
    public let timeout: Duration
    /// Can't be undone (sending): the runner counts down first, so Esc can still stop it.
    public let irreversible: Bool
    public let run: @MainActor (ActionContext) async throws -> Void

    public init(title: String, timeout: Duration, irreversible: Bool = false,
                run: @escaping @MainActor (ActionContext) async throws -> Void) {
        self.title = title
        self.timeout = timeout
        self.irreversible = irreversible
        self.run = run
    }
}

/// A step's own explanation of what went wrong, shown in the notch.
public struct StepFailure: Error, Equatable, LogSafeError {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public var logDescription: String { reason }
}

public enum ActionEvent: Equatable, Sendable {
    case started([String])
    case stepStarted(Int)
    case stepFinished(Int)
    /// Before an irreversible step: whole seconds left, and who it's going to.
    case countingDown(secondsLeft: Int, to: String?)
    case finished
    case failed(step: Int, reason: String)
    case cancelled
    /// The irreversible input was made but its result couldn't be confirmed (Esc or a timeout came after
    /// it): never reported as "nothing sent".
    case probablySent(reason: String)
}

public enum ActionOutcome: Equatable, Sendable {
    case done
    case cancelled
    case failed(step: String, reason: String)
    case probablySent(reason: String)
}

/// Runs an action's steps one by one, visibly: reports each step as it starts and finishes, gives every
/// step a timeout, waits behind a countdown before anything irreversible, and stops the moment it's
/// cancelled (Esc), leaving the screen as it is (SPEC §4.4, ADR 0006).
@MainActor
public final class ActionRunner {
    public var onEvent: (ActionEvent) -> Void = { _ in }
    public private(set) var lastEvent: ActionEvent?

    private let countdown: Duration
    private let tick: Duration
    private var cancelled = false
    private var current: Task<Void, Error>?

    public init(countdown: Duration, tick: Duration = .seconds(1)) {
        self.countdown = countdown
        self.tick = tick
    }

    public var isRunning: Bool { current != nil }

    public func cancel() {
        cancelled = true
        current?.cancel()
    }

    public func run(_ steps: [ActionStep]) async -> ActionOutcome {
        cancelled = false
        let context = ActionContext()
        context.isStopped = { [weak self] in self?.cancelled ?? true }
        emit(.started(steps.map(\.title)))
        for (index, step) in steps.enumerated() {
            if step.irreversible, await !countDown(to: context.recipient) { return stop() }
            guard !cancelled else { return stop() }
            emit(.stepStarted(index))
            guard !cancelled else { return stop() }  // cancelled as the step was announced
            let work = Task { @MainActor in
                try await withTimeout(step.timeout) { try await step.run(context) }
            }
            current = work
            defer { current = nil }
            do {
                try await work.value
            } catch {
                let reason = switch error {
                case is TimedOut: "\(step.title) took too long"
                case let failure as StepFailure: failure.reason
                default: "\(step.title) failed"
                }
                // Past the point of no return, nothing can be called "not done".
                if context.committed { return probablySent(reason: cancelled ? "Stopped after sending" : reason) }
                if cancelled { return stop() }
                return fail(index, step, reason: reason)
            }
            guard !cancelled || context.committed else { return stop() }
            emit(.stepFinished(index))
        }
        emit(.finished)
        return .done
    }

    /// False if cancelled during the countdown.
    private func countDown(to recipient: String?) async -> Bool {
        var left = countdown
        while left > .zero {
            guard !cancelled else { return false }
            let seconds = Int((Double(left.components.seconds) + Double(left.components.attoseconds) / 1e18).rounded(.up))
            emit(.countingDown(secondsLeft: max(seconds, 1), to: recipient))
            try? await Task.sleep(for: min(tick, left))
            left -= tick
        }
        return !cancelled
    }

    private func probablySent(reason: String) -> ActionOutcome {
        emit(.probablySent(reason: reason))
        return .probablySent(reason: reason)
    }

    private func stop() -> ActionOutcome {
        emit(.cancelled)
        return .cancelled
    }

    private func fail(_ index: Int, _ step: ActionStep, reason: String) -> ActionOutcome {
        emit(.failed(step: index, reason: reason))
        return .failed(step: step.title, reason: reason)
    }

    private func emit(_ event: ActionEvent) {
        lastEvent = event
        onEvent(event)
    }
}
