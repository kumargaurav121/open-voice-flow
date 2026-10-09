import Core
import ModelStore
import SwiftUI

/// One step at a time, centred: a symbol, a title, a line of explanation, the step's content, and a single
/// primary action bottom-right.
struct OnboardingView: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var flow: OnboardingFlow { model.flow }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(stepKey)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 24)),
                        removal: .opacity.combined(with: .offset(x: -24))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 560, height: 460)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 1), value: stepKey)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .welcome:
            StepLayout(symbol: "waveform", title: "Welcome to Open Voice Flow",
                       message: "Dictation for English, Hindi and Hinglish, in any app.") {
                VStack(alignment: .leading, spacing: 16) {
                    Feature(symbol: "keyboard", title: "Hold fn and speak",
                            detail: "Let go and your words appear where you're typing.")
                    Feature(symbol: "textformat.abc", title: "Always English letters",
                            detail: "Hindi comes out as Hinglish, never translated.")
                    Feature(symbol: "lock", title: "Private by design",
                            detail: "Speech and AI cleanup run on this Mac. Nothing is uploaded.")
                }
                .frame(maxWidth: 380)
            }
        case .permissions:
            StepLayout(symbol: "lock.shield", title: "Allow Access",
                       message: "Open Voice Flow needs three permissions. Each one ticks as soon as you allow it.") {
                VStack(spacing: 0) {
                    PermissionRow(permission: .microphone, detail: "Hears you while you hold fn.",
                                  granted: flow.permissions.microphone) { model.request(.microphone) }
                    Divider().padding(.leading, 44)
                    PermissionRow(permission: .accessibility, detail: "Types the text into the app you're using.",
                                  granted: flow.permissions.accessibility) { model.request(.accessibility) }
                    Divider().padding(.leading, 44)
                    PermissionRow(permission: .inputMonitoring, detail: "Notices when you hold fn.",
                                  granted: flow.permissions.inputMonitoring) { model.request(.inputMonitoring) }
                }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .download(let status):
            StepLayout(symbol: "arrow.down.circle", title: "Downloading Models",
                       message: "Speech recognition and AI cleanup models, about 6 GB. Every file is checked against its published checksum before it's used.") {
                DownloadStatusView(status: status, secondsLeft: model.downloadSecondsLeft)
            }
        case .preparing(let status):
            StepLayout(symbol: "cpu", title: "Preparing for This Mac",
                       message: "macOS optimises the speech model for this Mac's Neural Engine. This happens once and can take up to 15 minutes; after that it loads in seconds.") {
                PreparingStatusView(status: status, started: model.stageStarted)
            }
        case .tryIt(let dictated):
            StepLayout(symbol: "mic", title: "Try It",
                       message: "Click in the box, hold fn, say something, then let go.") {
                TryItBox(dictated: dictated)
            }
        case .finished:
            StepLayout(symbol: "checkmark.circle", title: "You're All Set", message: "Hold fn anywhere to dictate.") {
                EmptyView()
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            StepDots(current: flow.step.position, count: OnboardingFlow.Step.count)
            Spacer()
            switch flow.step {
            case .download(.failed), .preparing(.failed):
                Button("Try Again") { model.send(.retry) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            case .download, .preparing, .finished:
                EmptyView()
            case .tryIt(dictated: false):
                // Done waits for a real dictation; Skip is there if the mic or fn key isn't cooperating.
                Button("Skip") { model.send(.skip) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                Button(primaryTitle) {}
                    .controlSize(.large)
                    .disabled(true)
            default:
                Button(primaryTitle) { model.send(.continue) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!flow.canContinue)
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(height: 32)
    }

    private var primaryTitle: String {
        switch flow.step {
        case .welcome: "Get Started"
        case .tryIt: "Done"
        default: "Continue"
        }
    }

    /// Changes only when the step changes, not on every progress tick, so transitions run once per step.
    private var stepKey: Int { flow.step.position * 10 + (flow.step == .finished ? 1 : 0) }
}

// MARK: Pieces

private struct StepLayout<Content: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(height: 56)
            Text(title)
                .font(.title.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            content
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let detail: String
    let granted: Bool
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .opacity(granted ? 1 : 0)
                    .scaleEffect(granted ? 1 : 0.5)
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .opacity(granted ? 0 : 1)
            }
            .font(.title2)
            .frame(width: 28)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: granted)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Allow…", action: allow)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Allowed" : "Not allowed")
    }
}

private struct DownloadStatusView: View {
    let status: OnboardingFlow.DownloadStatus
    let secondsLeft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .running(let progress):
                ProgressView(value: progress?.fraction ?? 0)
                HStack {
                    Text(progress.map(Self.sizes) ?? "Starting…")
                    Spacer()
                    if let secondsLeft { Text(Self.remaining(secondsLeft)) }
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 400)
    }

    private static func sizes(_ progress: DownloadProgress) -> String {
        let format = ByteCountFormatStyle(style: .file)
        return "\(progress.downloaded.formatted(format)) of \(progress.total.formatted(format))"
    }

    private static func remaining(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 1 ? "About a minute left" : "About \(minutes) minutes left"
    }
}

private struct PreparingStatusView: View {
    let status: OnboardingFlow.PrepareStatus
    let started: Date
    /// The Hinglish model's first Neural Engine load took ~15-16 min on an M1 Pro.
    private static let typical: TimeInterval = 15 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .running:
                TimelineView(.periodic(from: started, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(started)
                    VStack(alignment: .leading, spacing: 8) {
                        // An estimate, held short of the end so it never claims to be done early.
                        ProgressView(value: min(elapsed / Self.typical, 0.95))
                        Text("\(Duration.seconds(Int(elapsed)).formatted(.time(pattern: .minuteSecond))) elapsed. You can keep using your Mac.")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 400)
    }
}

private struct TryItBox: View {
    /// Set by the app once a dictation was transcribed and inserted (typing in the box doesn't count).
    let dictated: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 96)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Your words appear here")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
            Label("Dictation works.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .opacity(dictated ? 1 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dictated)
        }
        .frame(maxWidth: 420)
        .onAppear { focused = true }
    }
}

private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
