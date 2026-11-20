import Foundation
import Testing
@testable import Core

@MainActor
struct ModeTests {
    let defaults = UserDefaults(suiteName: "ovf-mode-\(UUID().uuidString)")!

    @Test func aNewInstallStartsInEnglishWithTheUsualDefaults() {
        let mode = ModeStore(defaults: defaults).mode

        #expect(mode.language == .english)
        // Saved at once, so a later change of default doesn't switch this install.
        #expect(defaults.data(forKey: ModeStore.key) != nil)
        #expect(mode.cleanup == .off)
        #expect(mode.speech == .local)
        #expect(mode.cloudLLM == CloudLLM(service: .groq, model: nil))
        #expect(mode.hotkeys == Hotkeys(dictate: .fn, command: .rightOption))
    }

    @Test func isKeptAsOneValueAcrossLaunches() {
        let store = ModeStore(defaults: defaults)
        store.mode.language = .english
        store.mode.cleanup = .cloud
        store.mode.speech = .deepgram
        store.mode.cloudLLM = CloudLLM(service: .openAI, model: "gpt-4.1-mini")
        store.mode.hotkeys.dictate = .rightCommand

        #expect(ModeStore(defaults: defaults).mode == store.mode)
        #expect(defaults.data(forKey: ModeStore.key) != nil)
    }

    @Test func takesOverTheSettingsSavedBeforeModesExisted() {
        defaults.set("english", forKey: "language")
        defaults.set("thorough", forKey: "cleanupMode")

        let mode = ModeStore(defaults: defaults).mode

        #expect(mode.language == .english)
        #expect(mode.cleanup == .thorough)
        #expect(mode.speech == .local)
    }

    @Test func toleratesSettingsWrittenByANewerVersion() throws {
        let newer = """
            {"version": 7, "language": "english", "cleanup": "someday-mode", "speech": "deepgram",
             "hotkeys": {"dictate": "rightShift", "command": "a-key-from-the-future"}, "futureField": [1, 2]}
            """
        defaults.set(Data(newer.utf8), forKey: ModeStore.key)

        let mode = ModeStore(defaults: defaults).mode

        // Known values are kept; unknown ones fall back to their defaults.
        #expect(mode.language == .english)
        #expect(mode.speech == .deepgram)
        #expect(mode.cleanup == .off)
        #expect(mode.hotkeys == Hotkeys(dictate: .rightShift, command: .rightOption))
    }

    @Test func savedHotkeysThatWouldClashFallBackToTheDefaults() {
        // An unknown command key would default to Right ⌥, the same as dictate.
        defaults.set(Data(#"{"hotkeys": {"dictate": "rightOption", "command": "a-key-from-the-future"}}"#.utf8), forKey: ModeStore.key)

        #expect(ModeStore(defaults: defaults).mode.hotkeys == Hotkeys())
    }

    @Test func aStoredHinglishChoiceStaysHinglish() {
        defaults.set(Data(#"{"version": 1, "language": "hinglish", "cleanup": "off", "speech": "local"}"#.utf8), forKey: ModeStore.key)

        #expect(ModeStore(defaults: defaults).mode.language == .hinglish)
    }

    @Test func hinglishPickedBeforeModesExistedStaysHinglish() {
        defaults.set("hinglish", forKey: "language")

        #expect(ModeStore(defaults: defaults).mode.language == .hinglish)
    }

    @Test func settingsFromBeforeModesWithNoLanguageKeepHinglish() {
        // Hinglish was the default then; only a new install starts in English.
        defaults.set("fast", forKey: "cleanupMode")

        #expect(ModeStore(defaults: defaults).mode.language == .hinglish)
    }

    @Test func anInstallThatFinishedSetupBeforeModesExistedKeepsHinglish() {
        defaults.set(true, forKey: "onboardingComplete")

        #expect(ModeStore(defaults: defaults).mode.language == .hinglish)
        #expect(defaults.bool(forKey: "onboardingComplete"))  // still the app's setup state
    }

    @Test func anUnknownSavedLanguageFallsBackToEnglish() {
        defaults.set(Data(#"{"version": 1, "language": "a-language-from-the-future"}"#.utf8), forKey: ModeStore.key)

        #expect(ModeStore(defaults: defaults).mode.language == .english)
    }

    @Test func migratedSettingsAreSavedAsTheModeAndTheOldOnesRemoved() {
        defaults.set("english", forKey: "language")
        defaults.set("fast", forKey: "cleanupMode")

        _ = ModeStore(defaults: defaults)

        #expect(defaults.data(forKey: ModeStore.key) != nil)
        #expect(defaults.string(forKey: "language") == nil)
        #expect(defaults.string(forKey: "cleanupMode") == nil)
        #expect(ModeStore(defaults: defaults).mode.cleanup == .fast)
    }

    @Test func theSendCountdownIsKeptWithinOneToTenSeconds() {
        let store = ModeStore(defaults: defaults)
        #expect(store.mode.sendCountdown == 3)

        store.mode.sendCountdown = 5
        #expect(ModeStore(defaults: defaults).mode.sendCountdown == 5)

        store.mode.sendCountdown = 60
        #expect(store.mode.sendCountdown == 10)
        defaults.set(Data(#"{"sendCountdown": 0}"#.utf8), forKey: ModeStore.key)
        #expect(ModeStore(defaults: defaults).mode.sendCountdown == 1)
    }

    @Test func unreadableSettingsFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: ModeStore.key)

        #expect(ModeStore(defaults: defaults).mode == Mode())
    }

    @Test func playsTheReleaseSoundUnlessSwitchedOff() {
        let store = ModeStore(defaults: defaults)
        #expect(store.mode.releaseSound)

        store.mode.releaseSound = false

        #expect(ModeStore(defaults: defaults).mode.releaseSound == false)
    }

    @Test func settingsSavedBeforeTheReleaseSoundExistedPlayIt() {
        defaults.set(Data(#"{"version": 1, "language": "english", "cleanup": "off"}"#.utf8), forKey: ModeStore.key)

        #expect(ModeStore(defaults: defaults).mode.releaseSound)
    }
}
