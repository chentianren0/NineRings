import Foundation
@testable import Motion
import Puzzle
import Testing
import Toy

extension MotionTests {
    /// The scores: every move has one, its events are in order, inside their stages, where parts meet, and the rule for
    /// when an event sounds gives each event exactly once however the move is cut into steps.
    @Suite struct ScoreTests {
        /// Every legal move from every state, both ways: 511 moves, 1022 directions.
        static let allMoves: [Move] = (0..<512).flatMap { bits in
            PuzzleState.rings.compactMap { Move(ring: $0, from: PuzzleState(bits: UInt16(bits))) }
        }

        /// One move of each ring each way, where the ring first comes off, and its way back.
        static let written: [Move] = MoveMotion.written.flatMap { [$0, $0.reversed] }

        @Test func everyMoveHasAScoreInOrderAndInsideItsStages() {
            #expect(Self.allMoves.count == 1022)
            for move in Self.allMoves {
                let score = Score(move)
                let stages = MoveMotion(move).stages
                #expect(score.ring == move.ring && score.takesOff == move.takesOff)
                #expect(!score.events.isEmpty, "ring \(move.ring) from \(move.from) has no events")
                #expect(zip(score.events, score.events.dropFirst()).allSatisfy { $0.progress <= $1.progress })
                for event in score.events {
                    #expect(event.progress > 0 && event.progress <= 1, "\(event.what) at \(event.progress)")
                    #expect(event.strength > 0 && event.strength <= 1)
                    #expect(PuzzleState.rings.contains(event.ring))
                    let stage = stages.first { $0.key == event.stage }
                    #expect(stage?.contains(event.progress) == true, "\(event.what) at \(event.progress) is not in \(event.stage)")
                }
            }
        }

        /// Each move ends heard: a ring coming off comes to rest hanging, a ring going on comes to rest on the sword.
        @Test func everyMoveHasItsRest() {
            for move in Self.written {
                let rests = Score(move).events.filter { $0.kind == .rest && $0.ring == move.ring }
                #expect(rests.count == 1, "ring \(move.ring) \(move.takesOff ? "off" : "on")")
            }
        }

        /// Every strike and every rest is where its ring is within 1 mm of the sword or another part, at the smallest gap
        /// thereabouts; the sword is home where it is heard coming home. Ring 9 has no ring behind it to hang against, so
        /// its rest coming off is heard as it settles on its own rod, and only has to be at its stage.
        @Test func eventsAreWherePartsMeet() {
            for move in Self.written {
                let motion = MoveMotion(move)
                for event in Score(move).events {
                    let pose = motion.pose(at: event.progress)
                    if event.kind == .swordHome {
                        #expect(abs(pose.swordSlide - Layout.swordHome) < 0.05 && abs(pose.swordHeight) < 0.05, "\(event.what)")
                        continue
                    }
                    if event.ring == 9 && event.kind == .rest && move.takesOff { continue }
                    let gap = Self.gap(ring: event.ring, in: pose)
                    #expect(gap < 1, "\(event.what): \(gap) mm at \(event.progress)")
                    for neighbour in [event.progress - 0.004, event.progress + 0.004] where neighbour >= 0 && neighbour <= 1 {
                        let near = Self.gap(ring: event.ring, in: motion.pose(at: neighbour))
                        #expect(gap <= near + 0.05, "\(event.what): \(gap) mm at \(event.progress), \(near) mm at \(neighbour)")
                    }
                }
            }
        }

        static func gap(ring: Int, in pose: ToyPose) -> Double {
            min(ContactProbe.gap(ring: ring, toSword: pose), ContactProbe.gap(ring: ring, toOthers: pose))
        }

        // MARK: - The crossing rule

        /// Ways of cutting 0...1 into steps: even, uneven, very fine, and steps that land exactly on events.
        static func cuts(for score: Score) -> [[Double]] {
            let even = (0...7).map { Double($0) / 7 }
            var uneven = [0.0]
            var step = 0.0001
            while uneven.last! < 1 {
                uneven.append(min(1, uneven.last! + step))
                step = step < 0.2 ? step * 2.7 : 0.0003
            }
            let fine = (0...997).map { Double($0) / 997 }
            let onEvents = ([0] + score.events.map(\.progress) + [1]).sorted()
            return [[0, 1], even, uneven, fine, onEvents]
        }

        @Test func forwardEveryEventOnceInOrder() {
            for move in Self.written {
                let score = Score(move)
                for cut in Self.cuts(for: score) {
                    let heard = zip(cut, cut.dropFirst()).flatMap { Score.events(of: move, from: $0, to: $1) }
                    #expect(heard == score.events, "ring \(move.ring), \(cut.count - 1) steps")
                }
            }
        }

        /// Back, the toy runs the reversed move: undoing a ring going on sounds as that ring coming off does.
        @Test func backwardIsTheReversedMove() {
            for move in Self.written {
                let reversed = Score(move.reversed)
                for cut in Self.cuts(for: Score(move)) {
                    let back = cut.reversed()
                    let heard = zip(back, back.dropFirst()).flatMap { Score.events(of: move, from: $0, to: $1) }
                    #expect(heard == reversed.events, "ring \(move.ring), \(cut.count - 1) steps back")
                }
            }
        }

        @Test func standingStillIsSilentAndBackAndForthIsHeardEachTime() {
            let move = MoveMotion.written[1]
            let event = Score(move).events[0]
            #expect(Score.events(of: move, from: 0.5, to: 0.5).isEmpty)
            let there = Score.events(of: move, from: event.progress - 0.01, to: event.progress + 0.01)
            let back = Score.events(of: move, from: event.progress + 0.01, to: event.progress - 0.01)
            #expect(there.contains(event))
            #expect(back.count == 1)
        }

        // MARK: - Thinning

        /// At full speed every event of every move sounds, played straight through.
        @Test func atFullSpeedEveryEventSounds() {
            for move in Self.written {
                let timing = MoveMotion(move).timing
                var thinning = Thinning()
                for event in Score(move).events {
                    let admitted = thinning.admits(event, at: timing.time(atProgress: event.progress))
                    #expect(admitted, "\(event.what) at full speed")
                }
            }
        }

        /// Played at four times the speed, the shortest solution never sounds two events closer than the spacing, and
        /// thins out rather than rattling.
        @Test func atFourTimesTheSpeedItThinsOut() {
            var time = 0.0, thinning = Thinning(), heard = 0, sounded: [Double] = []
            var state = PuzzleState.allOn
            for ring in state.moves(to: .allOff) {
                guard let move = Move(ring: ring, from: state) else { Issue.record("no move"); return }
                let motion = MoveMotion(move)
                for event in Score(move).events {
                    heard += 1
                    let at = time + motion.timing.time(atProgress: event.progress) / 4
                    if thinning.admits(event, at: at) { sounded.append(at) }
                }
                time += motion.duration / 4
                state = move.to
            }
            let closest = zip(sounded, sounded.dropFirst()).map { $1 - $0 }.min() ?? .infinity
            #expect(closest >= Thinning.spacing - 1e-9)
            #expect(Double(sounded.count) / time < 10, "\(sounded.count) of \(heard) events in \(time) s")
            print(String(format: "at 4×: %d of %d events sound in %.1f s, %.1f a second; closest %.3f s", sounded.count, heard, time, Double(sounded.count) / time, closest))
        }

        @Test func thinningRule() {
            let main = Score.Event(kind: .strike, ring: 1, progress: 0.5, strength: 1, isDetail: false, stage: "", what: "")
            let detail = Score.Event(kind: .strike, ring: 1, progress: 0.5, strength: 1, isDetail: true, stage: "", what: "")
            var thinning = Thinning()
            let admitted = [(detail, 0.0), (main, 0.04), (main, 0.05), (detail, 0.12), (detail, 0.14)].map { thinning.admits($0, at: $1) }
            #expect(admitted == [true, false, true, false, true])
        }

        // MARK: - The sword's travel

        @Test func swordTravelFollowsTheSword() {
            for move in Self.written {
                let score = Score(move)
                #expect(score.swordTravel(at: 0) == 0)
                #expect(zip(score.swordTravel, score.swordTravel.dropFirst()).allSatisfy { $0 <= $1 })
                // Out and back: at least twice the farthest the sword slides.
                let farthest = (0...200).map { MoveMotion(move).pose(at: Double($0) / 200).swordSlide }.max()!
                #expect(score.totalSwordTravel >= 2 * farthest - 0.5)
                // The same either way.
                #expect(abs(score.totalSwordTravel - Score(move.reversed).totalSwordTravel) < 1e-6)
            }
        }
    }
}
