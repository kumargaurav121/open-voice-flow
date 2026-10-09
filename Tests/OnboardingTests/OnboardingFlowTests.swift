import Core
import ModelStore
import Testing
@testable import Onboarding

private let none = Permissions(microphone: false, accessibility: false, inputMonitoring: false)
private let all = Permissions(microphone: true, accessibility: true, inputMonitoring: true)

private func flow(permissions: Permissions = none, installed: Bool = false, prepared: Bool = false) -> OnboardingFlow {
    OnboardingFlow(permissions: permissions, modelsInstalled: installed, modelsPrepared: prepared)
}

@Suite struct OnboardingFlowTests {
    @Test func startsWithWelcomeThenPermissions() {
        var flow = flow()
        #expect(flow.step == .welcome)
        #expect(flow.handle(.continue) == [])
        #expect(flow.step == .permissions)
    }

    @Test func permissionsGateContinueAndUpdateLive() {
        var flow = flow()
        _ = flow.handle(.continue)
        #expect(!flow.canContinue)
        #expect(flow.handle(.continue) == [])
        #expect(flow.step == .permissions)

        _ = flow.handle(.permissionsChanged(Permissions(microphone: true, accessibility: false, inputMonitoring: false)))
        #expect(flow.permissions.microphone)
        #expect(!flow.canContinue)

        _ = flow.handle(.permissionsChanged(all))
        #expect(flow.canContinue)
    }

    @Test func downloadsAfterPermissionsThenPrepares() {
        var flow = flow(permissions: all)
        _ = flow.handle(.continue)
        #expect(flow.handle(.continue) == [.startDownload])
        #expect(flow.step == .download(.running(nil)))

        _ = flow.handle(.downloadProgress(DownloadProgress(downloaded: 5, total: 10)))
        #expect(flow.step == .download(.running(DownloadProgress(downloaded: 5, total: 10))))

        #expect(flow.handle(.downloadFinished) == [.startPreparing])
        #expect(flow.step == .preparing(.running))

        #expect(flow.handle(.prepared) == [])
        #expect(flow.step == .tryIt(dictated: false))
    }

    @Test func failedDownloadCanBeRetried() {
        var flow = flow(permissions: all)
        _ = flow.handle(.continue)
        _ = flow.handle(.continue)
        _ = flow.handle(.downloadFailed("Checksum mismatch"))
        #expect(flow.step == .download(.failed("Checksum mismatch")))

        #expect(flow.handle(.retry) == [.startDownload])
        #expect(flow.step == .download(.running(nil)))
    }

    @Test func failedPreparingCanBeRetried() {
        var flow = flow(permissions: all, installed: true)
        _ = flow.handle(.continue)
        #expect(flow.handle(.continue) == [.startPreparing])
        _ = flow.handle(.prepareFailed("Couldn't load"))
        #expect(flow.step == .preparing(.failed("Couldn't load")))

        #expect(flow.handle(.retry) == [.startPreparing])
        #expect(flow.step == .preparing(.running))
    }

    @Test func aFreshDownloadIsAlwaysLoadedBeforeTryIt() {
        // Compiled before (cached), but the app hasn't loaded these files yet.
        var flow = flow(permissions: all, prepared: true)
        _ = flow.handle(.continue)
        _ = flow.handle(.continue)

        #expect(flow.handle(.downloadFinished) == [.startPreparing])
        #expect(flow.step == .preparing(.running))
    }

    @Test func skipsDownloadAndPreparingWhenAlreadyDone() {
        var flow = flow(permissions: all, installed: true, prepared: true)
        _ = flow.handle(.continue)
        #expect(flow.handle(.continue) == [])
        #expect(flow.step == .tryIt(dictated: false))
    }

    @Test func tryItFinishesOnlyAfterARealDictation() {
        var flow = flow(permissions: all, installed: true, prepared: true)
        _ = flow.handle(.continue)
        _ = flow.handle(.continue)
        #expect(!flow.canContinue)
        #expect(flow.handle(.continue) == [])

        _ = flow.handle(.dictationSucceeded)
        #expect(flow.step == .tryIt(dictated: true))
        #expect(flow.canContinue)

        #expect(flow.handle(.continue) == [.markComplete])
        #expect(flow.step == .finished)
    }

    @Test func tryItCanBeSkipped() {
        var flow = flow(permissions: all, installed: true, prepared: true)
        _ = flow.handle(.continue)
        _ = flow.handle(.continue)

        #expect(flow.handle(.skip) == [.markComplete])
        #expect(flow.step == .finished)
    }

    @Test func eventsForOtherStepsAreIgnored() {
        var flow = flow(permissions: all)
        #expect(flow.handle(.downloadFinished) == [])
        #expect(flow.handle(.prepared) == [])
        #expect(flow.handle(.dictationSucceeded) == [])
        #expect(flow.handle(.skip) == [])
        #expect(flow.handle(.retry) == [])
        #expect(flow.step == .welcome)
    }
}
