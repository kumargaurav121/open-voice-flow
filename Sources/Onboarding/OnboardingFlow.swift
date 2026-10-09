import Core
import ModelStore

/// The first-run walkthrough as a state machine: Welcome → Permissions → Download → Preparing → Try it.
/// Pure logic; the window feeds it events (button presses, permission polls, download and load results)
/// and runs the effects it returns.
public struct OnboardingFlow: Equatable {
    public enum Step: Equatable {
        case welcome
        /// Live ✓ per permission; Continue once all are granted.
        case permissions
        case download(DownloadStatus)
        /// First load of the speech models: Core ML compiles them for this Mac once (minutes), then caches.
        case preparing(PrepareStatus)
        /// A box to dictate into. Done unlocks once a dictation has gone all the way through the app.
        case tryIt(dictated: Bool)
        case finished

        /// 0-based position for the step indicator.
        public var position: Int {
            switch self {
            case .welcome: 0
            case .permissions: 1
            case .download: 2
            case .preparing: 3
            case .tryIt, .finished: 4
            }
        }

        public static let count = 5
    }

    public enum DownloadStatus: Equatable {
        /// Nil until the first bytes are counted.
        case running(DownloadProgress?)
        case failed(String)
    }

    public enum PrepareStatus: Equatable {
        case running
        case failed(String)
    }

    public enum Event: Equatable {
        case `continue`
        case retry
        case permissionsChanged(Permissions)
        case downloadProgress(DownloadProgress)
        case downloadFinished
        case downloadFailed(String)
        case prepared
        case prepareFailed(String)
        /// The app transcribed and inserted a dictation.
        case dictationSucceeded
        /// Leave Try it without dictating.
        case skip
    }

    public enum Effect: Equatable {
        case startDownload
        case startPreparing
        /// Persist that onboarding is done, so it doesn't reappear on launch.
        case markComplete
    }

    public private(set) var step = Step.welcome
    public private(set) var permissions: Permissions
    private var modelsInstalled: Bool
    private var modelsPrepared: Bool

    public init(permissions: Permissions, modelsInstalled: Bool, modelsPrepared: Bool) {
        self.permissions = permissions
        self.modelsInstalled = modelsInstalled
        self.modelsPrepared = modelsPrepared
    }

    public var canContinue: Bool {
        switch step {
        case .welcome: true
        case .permissions: permissions.missing.isEmpty
        case .tryIt(let dictated): dictated
        case .download, .preparing, .finished: false
        }
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch (step, event) {
        case (_, .permissionsChanged(let current)):
            permissions = current
        case (.welcome, .continue):
            step = .permissions
        case (.permissions, .continue) where canContinue:
            return advancePastPermissions()
        case (.download, .downloadProgress(let progress)):
            step = .download(.running(progress))
        case (.download, .downloadFinished):
            // Always load what was just installed, even if an earlier compile is cached (then it's quick):
            // otherwise the first dictation would pay for the load.
            modelsInstalled = true
            step = .preparing(.running)
            return [.startPreparing]
        case (.download, .downloadFailed(let message)):
            step = .download(.failed(message))
        case (.download(.failed), .retry):
            step = .download(.running(nil))
            return [.startDownload]
        case (.preparing, .prepared):
            modelsPrepared = true
            step = .tryIt(dictated: false)
        case (.preparing, .prepareFailed(let message)):
            step = .preparing(.failed(message))
        case (.preparing(.failed), .retry):
            step = .preparing(.running)
            return [.startPreparing]
        case (.tryIt, .dictationSucceeded):
            step = .tryIt(dictated: true)
        case (.tryIt(dictated: true), .continue), (.tryIt, .skip):
            step = .finished
            return [.markComplete]
        default:
            break
        }
        return []
    }

    /// The next unfinished stage after permissions: whatever is already done is skipped.
    private mutating func advancePastPermissions() -> [Effect] {
        if !modelsInstalled {
            step = .download(.running(nil))
            return [.startDownload]
        }
        if !modelsPrepared {
            step = .preparing(.running)
            return [.startPreparing]
        }
        step = .tryIt(dictated: false)
        return []
    }
}
