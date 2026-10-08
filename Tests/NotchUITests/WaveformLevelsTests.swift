import Testing
@testable import NotchUI

struct WaveformLevelsTests {
    func levels(after decibels: [Float]) -> WaveformLevels {
        var levels = WaveformLevels()
        for db in decibels { levels.update(decibels: db) }
        return levels
    }

    @Test func silenceRestsAtAVisibleFloor() {
        let history = levels(after: Array(repeating: -90, count: 30)).history(count: 30)

        #expect(history.allSatisfy { $0 == WaveformLevels.floor })
    }

    @Test func loudSpeechFillsTheBars() {
        #expect(levels(after: Array(repeating: -8, count: 30)).history(count: 10).allSatisfy { $0 > 0.9 })
    }

    @Test func barsRiseImmediatelyWhenYouStartTalking() {
        #expect(levels(after: [-90, -90, -8]).level > 0.9)
    }

    @Test func barsFallGraduallyWhenYouStop() {
        let level = levels(after: [-8, -90]).level

        #expect(level < 0.9 && level > 0.5)
    }

    @Test func barsSettleToTheFloorAfterAPause() {
        #expect(levels(after: [-8] + Array(repeating: -90, count: 40)).level == WaveformLevels.floor)
    }

    @Test func historyScrollsWithTheNewestLevelOnTheRight() {
        let levels = levels(after: [-90, -90, -8])

        let history = levels.history(count: 4)

        #expect(history.count == 4)
        #expect(history.last! > 0.9)
        #expect(history.first! == WaveformLevels.floor)
    }

    @Test func historyIsPaddedWithTheFloorBeforeYouStartTalking() {
        #expect(WaveformLevels().history(count: 3) == Array(repeating: WaveformLevels.floor, count: 3))
    }
}
