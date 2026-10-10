import AppKit
import SwiftUI

/// Where the dictation is going and how it started; shown in the panel's camera row and timer.
struct DictationContext: Equatable {
    var appName: String
    var appIcon: NSImage?
    var mode: String
    var startedAt: Date
}

/// MacBook layout: the notch grown down into a panel. The camera row carries context either side of
/// the camera (target app, mode); the body below carries the state — mic, live waveform and timer while
/// listening, a rolling wave while transcribing, a ✓ when done, or the error.
struct NotchPanelBody: View {
    static let barCount = 30

    let model: NotchViewModel
    /// Width of the camera housing in the top row; 0 for the floating panel.
    let cameraWidth: CGFloat
    let headerHeight: CGFloat
    let shoulder: CGFloat
    let visible: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            cameraRow
                .frame(height: headerHeight)
            stateRow
                .frame(height: NotchGeometry.panelBodyHeight)
            if case .acting(let progress) = model.phase {
                ActionStepList(progress: progress, reduceMotion: reduceMotion)
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .transition(reduceMotion ? .opacity : .materialize)
            }
            if case .error(let error, true) = model.phase {
                Text(error.details)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .transition(reduceMotion ? .opacity : .materialize)
            }
        }
        .padding(.horizontal, shoulder)
        // Content materialises as the panel grows out of the notch, and dissolves back into it.
        .blur(radius: visible || reduceMotion ? 0 : 10)
        .scaleEffect(visible || reduceMotion ? 1 : 0.85, anchor: .top)
        .opacity(visible ? 1 : 0)
    }

    // MARK: Camera row: context beside the camera

    private var cameraRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let icon = model.context?.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                }
                Text(model.context?.appName ?? "")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)

            Color.clear.frame(width: cameraWidth)  // the camera

            Text(model.context?.mode ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.12)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 18)
        }
        .padding(.top, 2)
    }

    // MARK: State row

    private var stateRow: some View {
        HStack(spacing: 14) {
            StatusBadge(phase: model.phase, reduceMotion: reduceMotion)
            middle
                .frame(maxWidth: .infinity)
            trailing
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder private var middle: some View {
        switch model.phase {
        case .error(let error, _):
            Text(error.message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        case .acting(let progress):
            // Who and what, so the countdown below is never a surprise.
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.recipientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.interpolate)
                Text("“\(progress.message)”")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.35, dampingFraction: 1), value: progress.recipientName)
            .transition(.opacity)
        case .sent(let recipient, let confirmed):
            Text(confirmed ? "Sent to \(recipient ?? "Slack")" : "Probably sent: check Slack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .stopped:
            Text("Stopped, nothing sent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .command(let result):
            Text(result.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        default:
            ScrollingWaveform(phase: model.phase, levels: model.history, reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.phase {
        case .listening:
            if let started = model.context?.startedAt {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(started))),
                         format: .time(pattern: .minuteSecond))
                }
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
            }
        case .transcribing:
            Text("Transcribing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        case .inserted:
            Text("Inserted")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
        case .error(_, let expanded):
            Text(expanded ? "Close" : "Details")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        case .command:
            // The message (or, for an unknown command, the transcript) is on the clipboard.
            Text("Copied")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.cyan.opacity(0.8))
        case .acting(let progress):
            // The way out, always in view; it brightens while the countdown runs.
            KeyCap(label: "esc", emphasised: progress.secondsLeft != nil)
                .accessibilityLabel("Press Escape to stop")
        case .sent(_, let confirmed):
            Text(confirmed ? "Sent" : "Check")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(confirmed ? .green : .orange)
        case .stopped:
            EmptyView()
        case .idle:
            EmptyView()
        }
    }
}

/// An action's steps, one row each: ✓ done, a spinner on the one running, a hollow circle for what's
/// left. The send row turns into the countdown, a ring draining towards the send.
private struct ActionStepList: View {
    let progress: ActionProgress
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(progress.steps.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    StepGlyph(state: state(of: index), reduceMotion: reduceMotion)
                        .frame(width: 16, height: 16)
                    Text(label(index, title))
                        .font(.system(size: 13, weight: state(of: index) == .running ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(opacity(of: index)))
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 16)
                .accessibilityElement(children: .combine)
                .accessibilityValue(accessibilityValue(of: index))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 1), value: progress)
    }

    enum StepState: Equatable { case done, running, countdown(fraction: Double), pending }

    /// The countdown runs between the last finished step and the send, so the send row shows it.
    private func state(of index: Int) -> StepState {
        if index < progress.done { return .done }
        if let left = progress.secondsLeft, index == progress.done {
            return .countdown(fraction: Double(left) / Double(max(left, progress.countdownTotal, 1)))
        }
        if index == progress.current, progress.secondsLeft == nil { return .running }
        return .pending
    }

    private func label(_ index: Int, _ title: String) -> String {
        if case .countdown = state(of: index), let left = progress.secondsLeft { return "Sending in \(left)s" }
        return title
    }

    private func opacity(of index: Int) -> Double {
        switch state(of: index) {
        case .done: 0.55
        case .running, .countdown: 1
        case .pending: 0.35
        }
    }

    private func accessibilityValue(of index: Int) -> String {
        switch state(of: index) {
        case .done: "Done"
        case .running: "In progress"
        case .countdown: "Sending in \(progress.secondsLeft ?? 0) seconds"
        case .pending: "Waiting"
        }
    }
}

private struct StepGlyph: View {
    let state: ActionStepList.StepState
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            case .running:
                if reduceMotion {
                    Image(systemName: "circle.dotted").foregroundStyle(.cyan)
                } else {
                    ProgressView().controlSize(.mini).tint(.cyan)
                }
            case .countdown(let fraction):
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: fraction)
                }
                .padding(1)
            case .pending:
                Image(systemName: "circle").foregroundStyle(.white.opacity(0.3))
            }
        }
        .font(.system(size: 14, weight: .semibold))
    }
}

/// A small keyboard key, the way macOS shows shortcuts.
private struct KeyCap: View {
    let label: String
    let emphasised: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(emphasised ? 0.95 : 0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(emphasised ? 0.22 : 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .animation(.easeOut(duration: 0.2), value: emphasised)
    }
}

/// Leading badge: one circle whose symbol and tint morph through the states.
private struct StatusBadge: View {
    let phase: NotchStateMachine.Phase
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.2))
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: isBusy && !reduceMotion)
        }
        .frame(width: 34, height: 34)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: isError) { view, offset in
            view.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-5, duration: 0.07)
                SpringKeyframe(4, duration: 0.07)
                SpringKeyframe(-2, duration: 0.07)
                SpringKeyframe(0, duration: 0.12)
            }
        }
    }

    /// Listening, or working in another app: the badge pulses.
    private var isBusy: Bool {
        switch phase {
        case .listening, .acting: true
        default: false
        }
    }

    private var isError: Bool {
        if case .error = phase { return true }
        return false
    }

    private var symbol: String {
        switch phase {
        case .inserted: "checkmark"
        case .error: "exclamationmark"
        case .command(.parsed), .acting: "paperplane.fill"
        case .command(.unknown): "questionmark"
        case .sent(_, let confirmed): confirmed ? "checkmark" : "exclamationmark"
        case .stopped: "xmark"
        default: "mic.fill"
        }
    }

    private var tint: Color {
        switch phase {
        case .listening(.dictation): .orange
        case .listening(.command): .cyan
        case .transcribing, .idle: .white
        case .inserted: .green
        case .command, .acting: .cyan
        case .sent(_, let confirmed): confirmed ? .green : .orange
        case .stopped: .white
        case .error: Color(red: 1, green: 0.38, blue: 0.36)
        }
    }
}

/// Voice-Memos-style waveform: recent levels scroll in from the right while you speak; the same bars
/// roll as a wave while transcribing, then flatten when the text lands.
private struct ScrollingWaveform: View {
    let phase: NotchStateMachine.Phase
    let levels: [Float]
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: phase != .transcribing || reduceMotion)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(phase == .transcribing ? 0.55 : 0.95))
                        .frame(width: 3, height: 4 + 26 * height(index, at: context.date))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func height(_ index: Int, at date: Date) -> CGFloat {
        switch phase {
        case .listening:
            return CGFloat(levels[index])
        case .transcribing:
            guard !reduceMotion else { return 0.3 }
            let t = date.timeIntervalSinceReferenceDate
            return 0.15 + 0.35 * CGFloat(max(0, sin(t * 2 * .pi * 0.9 - Double(index) * 0.35)))
        default:
            return 0.05
        }
    }
}
