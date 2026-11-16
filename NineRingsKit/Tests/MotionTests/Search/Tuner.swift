import Foundation
@testable import Motion

/// Searches the free key values of a move for the path with the most room, with CMA-ES.
///
/// - Each candidate is scored with the fast room at `samples` points of the span. The points are shifted by a
///   random fraction of a step each generation, the same for the whole population, so that a path cannot win by
///   slipping a collision between two fixed points.
/// - A candidate that beats the best is scored again at four times as many points, and only that finer score
///   decides the best.
/// - The candidates of a generation are scored side by side, one per core.
/// - When a run settles (its spread is small, or the best has not improved for a while), it starts again from the
///   best with twice the population, which searches more widely (the "IPOP" restart).
enum Tuner {
    struct Result {
        var keys: KeyedMove.Keys
        var score: KeyedMove.Score
        var evaluations: Int
        var seconds: Double
        /// (seconds, least room) each time the best improved.
        var history: [(Double, Double)]
    }

    /// Writes the best keys so far, whole, to the file `NINE_RINGS_KEYS_OUT` names, or, on GitHub, to
    /// `tool-output/search-keys-<copy>.txt`: a run stopped part way leaves its last complete keys.
    static func saveToFile(_ keys: KeyedMove.Keys, _ score: KeyedMove.Score) {
        let environment = ProcessInfo.processInfo.environment
        var isFolder: ObjCBool = false
        let onGitHub = FileManager.default.fileExists(atPath: "tool-output", isDirectory: &isFolder) && isFolder.boolValue
        guard let path = environment["NINE_RINGS_KEYS_OUT"]
            ?? (onGitHub ? "tool-output/search-keys-\(environment["NINE_RINGS_COPY"] ?? "1").txt" : nil) else { return }
        let text = keys.keys.sorted().map { name in
            name + ":" + keys[name]!.map { String(format: "%.4f=%.3f", $0.0, $0.1) }.joined(separator: ",")
        }.joined(separator: ";")
        try? "\(score)\n\(text)\n".write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The seed for a run: `NINE_RINGS_SEED`, or the copy's number when the tool runs as several copies on GitHub.
    static var seed: UInt64 {
        let environment = ProcessInfo.processInfo.environment
        return UInt64(environment["NINE_RINGS_SEED"] ?? environment["NINE_RINGS_COPY"] ?? "1") ?? 1
    }

    static func run(
        _ move: KeyedMove,
        from start: KeyedMove.Keys,
        seconds budget: Double,
        samples: Int = 120,
        sigma: Double = 1,
        seed: UInt64 = 1,
        stopAt target: Double = .infinity,
        log: (String) -> Void = { print($0); fflush(stdout) },
        save: (KeyedMove.Keys, KeyedMove.Score) -> Void = Tuner.saveToFile
    ) -> Result {
        let clock = DispatchTime.now().uptimeNanoseconds
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - clock) / 1e9 }
        var random = SeededRandom(seed: seed)
        var bestKeys = start
        var best = move.score(start, samples: 4 * samples, detail: true)
        var history = [(elapsed(), best.least)]
        var evaluations = 1
        log(String(format: "%7.1f s  start: ", elapsed()) + "\(best)")

        var population: Int? = nil
        var restart = 0
        while elapsed() < budget && best.least < target {
            var strategy = CMAES(mean: move.vector(bestKeys), sigma: sigma, population: population.map { $0 * 2 })
            population = strategy.population
            var sinceImprovement = 0
            log(String(format: "%7.1f s  run %d, population %d", elapsed(), restart, strategy.population))
            while elapsed() < budget && best.least < target {
                let points = strategy.ask(using: &random)
                let base = bestKeys
                let offset = random.uniform()
                let candidates = points.map { move.keys($0, base: base) }
                let scores = Sweep.inParallel(candidates.count) { move.score(candidates[$0], samples: samples, offset: offset) }
                evaluations += candidates.count
                strategy.tell(points, scores.map(\.value))
                sinceImprovement += 1
                // Candidates that beat the best on this grid are checked on a finer one.
                let contenders = scores.indices.filter { scores[$0].least > best.least }.sorted { scores[$0].least > scores[$1].least }.prefix(3)
                for index in contenders {
                    let fine = move.score(candidates[index], samples: 4 * samples, detail: true)
                    evaluations += 4
                    if fine.least > best.least + 1e-5 {
                        (best, bestKeys, sinceImprovement) = (fine, candidates[index], 0)
                        history.append((elapsed(), best.least))
                        log(String(format: "%7.1f s  best ", elapsed()) + "\(best)")
                        save(bestKeys, best)
                    }
                }
                if strategy.spread < 0.02 || sinceImprovement > 60 { break }
            }
            restart += 1
        }
        log(String(format: "%7.1f s  done after %d path scores: ", elapsed(), evaluations) + "\(best)")
        return Result(keys: bestKeys, score: best, evaluations: evaluations, seconds: elapsed(), history: history)
    }
}
