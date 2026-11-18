import Puzzle

// What the toy taken up from another installation of the app needs of the play: when it may be replaced, and whether a
// kept toy is one nobody has touched.

extension PlayState {
    /// Whether the person's toy may be replaced by another installation's without their asking: nothing is playing, the
    /// lesson is closed, the rings are not being set and no congratulation shows. A toy is never replaced in the middle
    /// of a move, nor under something the person is looking at. Whether the slider is being dragged is the screen's to
    /// add.
    public var isCalm: Bool {
        !toy.isPlaying && lesson == nil && !isSettingRings && !isCongratulating
    }
}

extension ToySnapshot {
    /// Whether nobody has touched the toy: every ring on, no move made or in hand, nothing waiting, no journey under way,
    /// and a play, if any, that has counted nothing. Such a toy is the one a first launch has, and every other toy was
    /// made knowing it.
    public var isUntouched: Bool {
        guard start.state == .allOn, moves.isEmpty, slider == nil, queue.isEmpty, !isSolving, journeys.isEmpty else {
            return false
        }
        guard let play else { return true }
        return play.moves == 0 && play.undos == 0 && play.movesPlayedForThePerson == 0
    }
}
