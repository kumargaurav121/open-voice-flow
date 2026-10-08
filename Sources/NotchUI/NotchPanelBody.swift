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
        case .idle:
            EmptyView()
        }
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
                .symbolEffect(.pulse, options: .repeating, isActive: isListening && !reduceMotion)
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

    private var isListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    private var isError: Bool {
        if case .error = phase { return true }
        return false
    }

    private var symbol: String {
        switch phase {
        case .inserted: "checkmark"
        case .error: "exclamationmark"
        default: "mic.fill"
        }
    }

    private var tint: Color {
        switch phase {
        case .listening(.dictation): .orange
        case .listening(.command): .cyan
        case .transcribing, .idle: .white
        case .inserted: .green
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
