#if DEBUG || STORE_TOOLS
/// When a store picture may be taken: once the toy has been drawn for a while and nothing on the screen has changed
/// for long enough that every animation has ended.
///
/// The app shows it a signature of what is on the screen several times a second: the pose, the camera, whether a move
/// plays, the lesson's step and the congratulation. Any animation the screen runs starts with a change of one of
/// them, and the longest (the cover over the toy, a camera flight, the card coming up) ends well within `settle`.
/// Once ready, it stays ready.
struct StoreReadiness<Signature: Equatable> {
    /// How long nothing may change before the picture is taken, in seconds.
    var settle: Double = 1.5
    /// How many frames the 3D view must have drawn first, so that the toy is on the screen, not only made.
    var minimumFrames = 30

    private var signature: Signature?
    private var since = 0.0
    private(set) var isReady = false

    init(settle: Double = 1.5, minimumFrames: Int = 30) {
        self.settle = settle
        self.minimumFrames = minimumFrames
    }

    /// Takes in what the screen shows at `time`, in seconds, and how many frames the 3D view has drawn. Returns
    /// whether the picture may be taken.
    @discardableResult
    mutating func observe(_ signature: Signature, at time: Double, drawnFrames: Int) -> Bool {
        guard !isReady else { return true }
        // The time counts from the last moment the screen changed or the toy had not yet been drawn enough.
        if signature != self.signature || drawnFrames < minimumFrames {
            self.signature = signature
            since = time
            return false
        }
        isReady = time - since >= settle
        return isReady
    }
}
#endif
