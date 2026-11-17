import Testing
import Toy

/// The playback's rules about time: a stale speed is silent, several toys give the fastest good speed, a failed
/// engine start is not retried every frame and leads to a rebuild, and a late sound is dropped.
@Suite struct PlaybackRulesTests {
    /// Frames that stop with the sword moving leave the slide silent a quarter second later, not hissing on.
    @Test func aSpeedNoLongerSetFallsSilent() {
        #expect(PlaybackRules.slideSpeed(120, age: 0.016) == 120)
        #expect(PlaybackRules.slideSpeed(120, age: 0.24) == 120)
        #expect(PlaybackRules.slideSpeed(120, age: 0.25) == 0)
        #expect(PlaybackRules.slideSpeed(120, age: 30) == 0)
        #expect(PlaybackRules.slideSpeed(-5, age: 0) == 0)
    }

    /// Two windows: one still, one sliding. The slide follows the sliding one, whichever set its speed last, and
    /// forgets a window that has stopped setting it.
    @Test func severalToysGiveTheFastestGoodSpeed() {
        #expect(PlaybackRules.slideSpeed([(speed: 0, age: 0.001), (speed: 90, age: 0.010)]) == 90)
        #expect(PlaybackRules.slideSpeed([(speed: 90, age: 0.010), (speed: 0, age: 0.001)]) == 90)
        #expect(PlaybackRules.slideSpeed([(speed: 0, age: 0.001), (speed: 900, age: 2)]) == 0)
        #expect(PlaybackRules.slideSpeed([]) == 0)
    }

    /// A failed start is tried again only after a pause, however often it is asked for, and the second failure in a
    /// row asks for a rebuild.
    @Test func aFailedStartWaitsAndThenRebuilds() {
        var starts = EngineStarts()
        #expect(starts.mayTry(at: 0))
        let first = starts.failed(at: 0)
        #expect(!first)
        // Every frame of the next second asks again: none may try.
        let frames = stride(from: 1.0 / 120, to: EngineStarts.pause, by: 1.0 / 120)
        #expect(frames.allSatisfy { !starts.mayTry(at: $0) })
        #expect(starts.mayTry(at: EngineStarts.pause))
        let second = starts.failed(at: EngineStarts.pause)
        #expect(second, "a second failure in a row builds the engine afresh")
        #expect(starts.failures == 0)
        // A start that works forgets the failures.
        let afterRebuild = starts.failed(at: 5)
        #expect(!afterRebuild)
        starts.started()
        #expect(starts.mayTry(at: 5) && starts.failures == 0)
        let afterStart = starts.failed(at: 6)
        #expect(!afterStart)
    }

    /// A sound that waited longer than a tenth of a second is not played late.
    @Test func aLateSoundIsDropped() {
        #expect(PlaybackRules.isFresh(requested: 10, now: 10.05))
        #expect(!PlaybackRules.isFresh(requested: 10, now: 10.5))
    }
}
