import Puzzle
import Toy
import simd

/// What a move sounds like, written as its motion is: a short list of events, each at a fixed progress of the move.
///
/// An event says what happens (a ring strikes the sword, a ring comes to rest, the sword is home), which ring sounds
/// and how strongly. It holds no sound: the voices are elsewhere, and whoever plays the move turns events into sound and
/// touch. Like the poses, a score is a pure function of the move, so the same progress always holds the same events.
///
/// Each event is written where the written motion brings two parts together: at a smallest gap between the ring and
/// the sword, or the ring and another ring or rod, along the path. `ContactSearchTests` is the tool that found them
/// (run it with `NINE_RINGS_CONTACTS=1`), and they are written here as plain numbers, along the path's own parameter,
/// for ring 1's move and the second ring's (the same path for rings 2 to 9). A move's progress there comes from its
/// pacing, as its stages' does.
///
/// A ring going on runs the path of its coming off backwards, so it passes the same contacts in the reverse order.
/// What happens at a contact can differ by the way it is passed: a ring that comes to rest hanging as it comes off
/// only leaves that rest as it goes on, silently, and a ring going on comes to rest on the sword where, coming off,
/// it leaves the sword.
public struct Score: Sendable, Equatable {
    /// One thing that is heard, at one progress of the move.
    public struct Event: Sendable, Equatable {
        public enum Kind: String, Sendable, CaseIterable {
            /// A ring strikes the sword or another ring: the ring's own ringing.
            case strike
            /// A ring comes to rest, on the sword or hanging: a softer, lower knock.
            case rest
            /// The sword comes home and stops: a faint, low click.
            case swordHome
        }

        public let kind: Kind
        /// The ring whose voice sounds; for the sword, the ring that moves.
        public let ring: Int
        /// Where in the move it happens, from 0 to 1. Never 0: an event at the very start of a move would sound
        /// when nothing has happened yet.
        public let progress: Double
        /// How strongly, from 0 to 1.
        public let strength: Double
        /// Whether the event is a detail, which thins out first when events come close together (see ``Thinning``).
        public let isDetail: Bool
        /// The key of the stage the event happens in, as the move's stages name it.
        public let stage: String
        /// What happens, in English, for the sound bench and the tests.
        public let what: String
    }

    /// The ring that moves.
    public let ring: Int
    /// Whether the ring comes off; otherwise it goes on.
    public let takesOff: Bool
    /// The events in the order the move reaches them.
    public let events: [Event]
    /// How far the sword has travelled, in millimetres, at evenly spaced progress from 0 to 1: the length of its path
    /// so far, sliding and moving down and up. The sword's slide is heard as it moves, so whoever plays the move
    /// reads how fast it goes from here.
    public let swordTravel: [Double]

    /// The score of `move`. It depends only on the ring and on which way it moves, not on the rings behind.
    public init(_ move: Move) {
        self = Self.book[Self.index(ring: move.ring, takesOff: move.takesOff)]
    }

    private init(ring: Int, takesOff: Bool, events: [Event], swordTravel: [Double]) {
        self.ring = ring
        self.takesOff = takesOff
        self.events = events
        self.swordTravel = swordTravel
    }

    /// Works out every score now, so that the first move played does not wait for it. Safe from any thread.
    public static func prepare() {
        _ = book
    }

    /// How far the sword has travelled by `progress`, in millimetres.
    public func swordTravel(at progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        let position = clamped * Double(swordTravel.count - 1)
        let index = min(Int(position), swordTravel.count - 2)
        let fraction = position - Double(index)
        return swordTravel[index] + (swordTravel[index + 1] - swordTravel[index]) * fraction
    }

    /// How far the sword travels in the whole move, in millimetres.
    public var totalSwordTravel: Double { swordTravel[swordTravel.count - 1] }

    /// The events passed in going from progress `start` to progress `end` of this score's move, forward: those after
    /// `start` and up to `end`, in order. However a stretch is cut into steps, every event in it comes out exactly
    /// once, in order. Going backward gives nothing here; see ``Score/events(of:from:to:)``.
    public func events(after start: Double, through end: Double) -> [Event] {
        guard end > start else { return [] }
        return events.filter { $0.progress > start && $0.progress <= end }
    }

    /// The events heard in going from progress `start` to progress `end` of `move`, either way.
    ///
    /// Forward, they are the move's own events after `start` and up to `end`. Backward, the toy runs the move back,
    /// which is the same ring moving the other way: so they are the events of the reversed move, whose progress is
    /// one minus this move's, after `1 − start` and up to `1 − end`. Undoing a ring going on sounds as that ring coming
    /// off does. Each way, however the stretch is cut into steps, every event in it comes out exactly once, in order;
    /// a stretch passed forward and then back is heard both times.
    public static func events(of move: Move, from start: Double, to end: Double) -> [Event] {
        if end > start { return Score(move).events(after: start, through: end) }
        if end < start { return Score(move.reversed).events(after: 1 - start, through: 1 - end) }
        return []
    }

    // MARK: - The written contacts

    /// A place along the path where parts meet, and what is heard there each way. Ring numbers are given relative to
    /// the moving ring: 0 is the ring that moves, −1 the ring in front of it.
    struct Contact {
        /// Where along the path's own parameter.
        let path: Double
        /// The index of the stage it is in, among the stages of coming off.
        let stage: Int
        let off: Sound?
        let on: Sound?

        struct Sound {
            let kind: Event.Kind
            let ring: Int
            let strength: Double
            let isDetail: Bool
            let what: String

            static func strike(_ strength: Double, detail: Bool = false, ring: Int = 0, _ what: String) -> Sound {
                Sound(kind: .strike, ring: ring, strength: strength, isDetail: detail, what: what)
            }

            static func rest(_ strength: Double, ring: Int = 0, _ what: String) -> Sound {
                Sound(kind: .rest, ring: ring, strength: strength, isDetail: false, what: what)
            }

            static func swordHome(_ strength: Double) -> Sound {
                Sound(kind: .swordHome, ring: 0, strength: strength, isDetail: false, what: "The sword is home")
            }
        }

        static func both(_ path: Double, stage: Int, _ sound: Sound) -> Contact {
            Contact(path: path, stage: stage, off: sound, on: sound)
        }
    }

    /// Ring 1's move, along its path. Its stages: flatten, over the tip, back over the slot, turn, down through the
    /// slot, hang. The ring lifts clear of the tip, at more than 1 mm, as the sword slides under it, so the tip is
    /// silent; it touches in the slot and comes to rest against ring 2's lower arc.
    static let ringOneContacts: [Contact] = [
        // Going on, the move ends with the ring lying on the sword again as the sword comes home: one sound.
        Contact(path: 0, stage: 0, off: nil, on: .rest(0.55, "Ring 1 comes to rest on the sword")),
        Contact(path: 0.40, stage: 2, off: .swordHome(0.3), on: nil),
        .both(0.678, stage: 4, .strike(0.45, detail: true, "Ring 1 touches a rail, going into the slot")),
        .both(0.7515, stage: 4, .strike(0.7, "Ring 1 strikes the rails in the slot")),
        .both(0.783, stage: 4, .strike(0.35, detail: true, "Ring 1 brushes ring 2")),
        Contact(path: 0.952, stage: 5, off: .rest(0.6, "Ring 1 comes to rest, hanging"), on: nil),
    ]

    /// The second ring's move, along its path. Its stages: the sword moves away, ring k over the tip, down through
    /// the slot, ring k hangs, the sword comes back. As the sword slides back and dips, ring k−1 rests on it until its
    /// tip leaves it; ring k touches the tip as it begins to swing up over it, touches the rails three times going
    /// down through the slot, and comes to rest hanging. Coming back up, the sword's tip enters ring k−1, which settles
    /// on it again.
    static let pairContacts: [Contact] = [
        Contact(path: 0, stage: 0, off: nil, on: .swordHome(0.3)),
        Contact(path: 0.12, stage: 0, off: nil, on: .rest(0.4, ring: -1, "Ring {k−1} settles on the sword again")),
        Contact(
            path: 0.283, stage: 1,
            off: .strike(0.5, "Ring {k} touches the tip as it swings up"),
            on: .rest(0.55, "Ring {k} comes to rest on the sword")
        ),
        .both(0.6285, stage: 2, .strike(0.35, detail: true, "Ring {k} touches a rail in the slot")),
        .both(0.6855, stage: 2, .strike(0.5, detail: true, "Ring {k} touches the other rail")),
        .both(0.7315, stage: 2, .strike(0.7, "Ring {k} strikes the rails in the slot")),
        Contact(path: 0.7975, stage: 3, off: .rest(0.65, "Ring {k} comes to rest, hanging"), on: nil),
        Contact(path: 0.95, stage: 4, off: .rest(0.4, ring: -1, "Ring {k−1} settles on the sword again"), on: nil),
        Contact(path: 1, stage: 4, off: .swordHome(0.3), on: nil),
    ]

    // MARK: - The book of scores

    /// How many points `swordTravel` holds.
    static let travelSamples = 241

    /// Every score: for each ring, coming off and going on.
    static let book: [Score] = PuzzleState.rings.flatMap { ring in
        [true, false].map { written(ring: ring, takesOff: $0) }
    }

    static func index(ring: Int, takesOff: Bool) -> Int {
        (ring - 1) * 2 + (takesOff ? 0 : 1)
    }

    /// The score of ring `ring` moving, worked out from the written contacts and the move's pacing and stages.
    static func written(ring: Int, takesOff: Bool) -> Score {
        let pacing = ring == 1 ? RingOneOff.pacing : PairMoveOff.paced[ring - 2].pacing
        let contacts = ring == 1 ? ringOneContacts : pairContacts
        let offStages = ring == 1 ? RingOneOff.stages : PairMoveOff.stages(ring: ring)
        let place = ring == 1 ? PuzzleState.allOn : PairMoveOff.firstPlace(ring)
        guard let off = Move(ring: ring, from: place) else { preconditionFailure("ring \(ring) comes off from its first place") }
        let move = takesOff ? off : off.reversed
        let stages = MoveMotion(move).stages
        var events: [Event] = []
        for contact in contacts {
            guard let sound = takesOff ? contact.off : contact.on else { continue }
            let offProgress = pacing.progress(atPathParameter: contact.path)
            let stage = takesOff ? contact.stage : offStages.count - 1 - contact.stage
            events.append(Event(
                kind: sound.kind,
                ring: ring + sound.ring,
                progress: takesOff ? offProgress : 1 - offProgress,
                strength: sound.strength,
                isDetail: sound.isDetail,
                stage: stages[stage].key,
                what: Self.named(sound.what, ring: ring)
            ))
        }
        // In the order the move reaches them; events at the same progress keep their written order.
        let ordered = events.enumerated().sorted { ($0.element.progress, $0.offset) < ($1.element.progress, $1.offset) }.map(\.element)
        return Score(ring: ring, takesOff: takesOff, events: ordered, swordTravel: travel(of: MoveMotion(move)))
    }

    /// The sword's travel along `motion`, at evenly spaced progress.
    static func travel(of motion: MoveMotion) -> [Double] {
        var travelled = 0.0
        var last = motion.pose(at: 0).swordOffset
        return (0..<travelSamples).map { index in
            let offset = motion.pose(at: Double(index) / Double(travelSamples - 1)).swordOffset
            travelled += simd_distance(offset, last)
            last = offset
            return travelled
        }
    }

    /// A contact's words with the ring numbers filled in.
    private static func named(_ what: String, ring: Int) -> String {
        what.replacingOccurrences(of: "{k−1}", with: String(ring - 1)).replacingOccurrences(of: "{k}", with: String(ring))
    }
}
