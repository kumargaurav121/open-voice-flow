import Core
import Foundation
import ModelStore

/// What onboarding needs from the app; the real ones are system permissions, the model downloader and the
/// speech pipeline.
@MainActor
public struct OnboardingServices {
    public var permissions: () -> Permissions
    /// Shows the system prompt where macOS still allows one, otherwise opens the System Settings pane.
    public var request: (Permission) -> Void
    public var downloadModels: (@escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    /// Loads the speech models once, so Core ML compiles them for this Mac.
    public var prepareModels: () async throws -> Void
    public var markComplete: () -> Void

    public init(permissions: @escaping () -> Permissions, request: @escaping (Permission) -> Void,
                downloadModels: @escaping (@escaping @Sendable (DownloadProgress) -> Void) async throws -> Void,
                prepareModels: @escaping () async throws -> Void, markComplete: @escaping () -> Void) {
        self.permissions = permissions
        self.request = request
        self.downloadModels = downloadModels
        self.prepareModels = prepareModels
        self.markComplete = markComplete
    }
}

/// Runs the flow: feeds it events and carries out its effects.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var flow: OnboardingFlow
    /// When the current download or first load started, for time estimates.
    private(set) var stageStarted = Date()
    /// When the first network bytes of this download arrived; the rate is timed from there.
    private var firstFetch: Date?
    /// The downloader reports every chunk from its own threads; the window reads the latest a few times a
    /// second, so progress stays in order and SwiftUI isn't asked to redraw thousands of times.
    @ObservationIgnored private let latestProgress = LatestProgress()
    @ObservationIgnored private var progressPoll: Timer?
    private let services: OnboardingServices
    @ObservationIgnored private var permissionPoll: Timer?
    @ObservationIgnored public var onFinished: () -> Void = {}

    public init(services: OnboardingServices, modelsInstalled: Bool, modelsPrepared: Bool) {
        self.services = services
        flow = OnboardingFlow(permissions: services.permissions(), modelsInstalled: modelsInstalled, modelsPrepared: modelsPrepared)
    }

    public func send(_ event: OnboardingFlow.Event) {
        for effect in flow.handle(event) { run(effect) }
    }

    func request(_ permission: Permission) { services.request(permission) }

    /// Permission grants happen in System Settings, so check while the window is up.
    public func startWatchingPermissions() {
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        let current = services.permissions()
        if current != flow.permissions { send(.permissionsChanged(current)) }
    }

    public func stopWatchingPermissions() {
        permissionPoll?.invalidate()
        permissionPoll = nil
    }

    /// The app calls this when a dictation was transcribed and inserted.
    public func dictationSucceeded() { send(.dictationSucceeded) }

    /// Seconds left at this run's network rate, once there's enough to go on.
    var downloadSecondsLeft: Double? {
        guard case .download(.running(let progress?)) = flow.step, let firstFetch, progress.fetched > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(firstFetch)
        guard elapsed > 3 else { return nil }
        return Double(progress.total - progress.downloaded) / (Double(progress.fetched) / elapsed)
    }

    private func run(_ effect: OnboardingFlow.Effect) {
        switch effect {
        case .startDownload:
            stageStarted = Date()
            firstFetch = nil
            latestProgress.clear()
            progressPoll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.showLatestProgress() }
            }
            let latestProgress = latestProgress
            Task {
                do {
                    try await services.downloadModels { latestProgress.set($0) }
                    finishProgress()
                    send(.downloadFinished)
                } catch {
                    finishProgress()
                    send(.downloadFailed(Self.message(for: error)))
                }
            }
        case .startPreparing:
            stageStarted = Date()
            Task {
                do {
                    try await services.prepareModels()
                    send(.prepared)
                } catch {
                    send(.prepareFailed("The speech model couldn't load: \(error.localizedDescription)"))
                }
            }
        case .markComplete:
            services.markComplete()
            onFinished()
        }
    }

    private func showLatestProgress() {
        guard let progress = latestProgress.value, flow.step != .download(.running(progress)) else { return }
        if firstFetch == nil, progress.fetched > 0 { firstFetch = Date() }
        send(.downloadProgress(progress))
    }

    private func finishProgress() {
        progressPoll?.invalidate()
        progressPoll = nil
        showLatestProgress()
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let mismatch as ModelDownloader.ChecksumMismatch:
            "\(mismatch.localizedDescription), so that model's download was deleted and nothing from it was installed. Try Again downloads it fresh."
        case let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost:
            "The connection dropped. What's downloaded so far is kept; Try Again picks up where it stopped."
        default:
            "The download stopped: \(error.localizedDescription). Try Again picks up where it stopped."
        }
    }
}

/// The newest progress report, written from the downloader's threads and read on the main actor.
private final class LatestProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: DownloadProgress?

    var value: DownloadProgress? { lock.withLock { latest } }
    func set(_ progress: DownloadProgress) { lock.withLock { latest = progress } }
    func clear() { lock.withLock { latest = nil } }
}
