import Foundation

/// The covariance matrix adaptation evolution strategy (CMA-ES), which maximises a function of a few dozen numbers
/// that has no gradient to follow and many local bumps, such as the least room along a path.
///
/// Each generation it draws a population of points from a normal distribution, scores them, and moves the
/// distribution's middle toward the best of them. It also learns the distribution's shape from the steps that
/// worked, so that it can travel along narrow ridges where every single number is already at its best and only
/// changing several together helps; this is where nudging one number at a time gets stuck. The step size grows
/// while steps keep pointing the same way and shrinks when they cancel.
///
/// This follows Hansen's tutorial (2016) and its `purecma` reference, with the default settings.
struct CMAES {
    let dimension: Int
    let population: Int
    let parents: Int
    private let weights: [Double]
    private let effective: Double
    private let cc, cs, c1, cmu, damping, expectedLength: Double

    private(set) var mean: [Double]
    private(set) var sigma: Double
    private var covariance: [[Double]]
    private var basis: [[Double]]
    private var scales: [Double]
    private var pathC: [Double]
    private var pathS: [Double]
    private var generation = 0
    private var evaluationsAtDecomposition = 0
    private var evaluations = 0

    init(mean: [Double], sigma: Double, population: Int? = nil) {
        let n = mean.count
        dimension = n
        let lambda = population ?? (4 + Int(3 * log(Double(n))))
        self.population = lambda
        parents = lambda / 2
        let raw = (0..<(lambda / 2)).map { log(Double(lambda + 1) / 2) - log(Double($0 + 1)) }
        let sum = raw.reduce(0, +)
        let weights = raw.map { $0 / sum }
        self.weights = weights
        let effective = 1 / weights.reduce(0) { $0 + $1 * $1 }
        self.effective = effective
        let nd = Double(n)
        cc = (4 + effective / nd) / (nd + 4 + 2 * effective / nd)
        cs = (effective + 2) / (nd + effective + 5)
        c1 = 2 / ((nd + 1.3) * (nd + 1.3) + effective)
        cmu = min(1 - c1, 2 * (effective - 2 + 1 / effective) / ((nd + 2) * (nd + 2) + effective))
        damping = 1 + 2 * max(0, ((effective - 1) / (nd + 1)).squareRoot() - 1) + cs
        expectedLength = nd.squareRoot() * (1 - 1 / (4 * nd) + 1 / (21 * nd * nd))
        self.mean = mean
        self.sigma = sigma
        let identity: [[Double]] = (0..<n).map { i in (0..<n).map { i == $0 ? 1 : 0 } }
        covariance = identity
        basis = identity
        scales = Array(repeating: 1, count: n)
        pathC = Array(repeating: 0, count: n)
        pathS = Array(repeating: 0, count: n)
    }

    /// A new population to score.
    mutating func ask(using random: inout SeededRandom) -> [[Double]] {
        decomposeIfDue()
        return (0..<population).map { _ in
            let z = (0..<dimension).map { _ in random.normal() }
            let scaled = (0..<dimension).map { scales[$0] * z[$0] }
            return (0..<dimension).map { i in
                mean[i] + sigma * (0..<dimension).reduce(0) { $0 + basis[i][$1] * scaled[$1] }
            }
        }
    }

    /// Learns from the scores of the population `ask` gave, higher being better.
    mutating func tell(_ points: [[Double]], _ scores: [Double]) {
        let n = dimension
        evaluations += points.count
        generation += 1
        let order = scores.indices.sorted { scores[$0] > scores[$1] }
        let old = mean
        mean = (0..<n).map { i in (0..<parents).reduce(0) { $0 + weights[$1] * points[order[$1]][i] } }
        let step = (0..<n).map { (mean[$0] - old[$0]) / sigma }

        // C^(-1/2) times the step, through the basis: B D^-1 B^T y.
        let inBasis = (0..<n).map { j in (0..<n).reduce(0) { $0 + basis[$1][j] * step[$1] } / scales[j] }
        let whitened = (0..<n).map { i in (0..<n).reduce(0) { $0 + basis[i][$1] * inBasis[$1] } }
        let csFactor = (cs * (2 - cs) * effective).squareRoot()
        pathS = (0..<n).map { (1 - cs) * pathS[$0] + csFactor * whitened[$0] }
        let lengthS = pathS.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let hsig = lengthS / (1 - pow(1 - cs, 2 * Double(generation))).squareRoot() / expectedLength < 1.4 + 2 / (Double(n) + 1)
        let ccFactor = (cc * (2 - cc) * effective).squareRoot()
        pathC = (0..<n).map { (1 - cc) * pathC[$0] + (hsig ? ccFactor * step[$0] : 0) }

        let correction = hsig ? 0 : cc * (2 - cc)
        let steps = (0..<parents).map { k in (0..<n).map { (points[order[k]][$0] - old[$0]) / sigma } }
        for i in 0..<n {
            for j in 0...i {
                var rankMu = 0.0
                for k in 0..<parents { rankMu += weights[k] * steps[k][i] * steps[k][j] }
                let value = (1 - c1 - cmu) * covariance[i][j] + c1 * (pathC[i] * pathC[j] + correction * covariance[i][j]) + cmu * rankMu
                covariance[i][j] = value
                covariance[j][i] = value
            }
        }
        sigma *= exp(min(1, (cs / damping) * (lengthS / expectedLength - 1)))
    }

    /// The largest scale of the distribution in any direction.
    var spread: Double { sigma * (scales.max() ?? 1) }

    private mutating func decomposeIfDue() {
        guard Double(evaluations - evaluationsAtDecomposition) > Double(population) / ((c1 + cmu) * Double(dimension) * 10) else { return }
        evaluationsAtDecomposition = evaluations
        let (values, vectors) = Self.eigen(covariance)
        basis = vectors
        scales = values.map { max($0, 1e-20).squareRoot() }
    }

    /// The eigenvalues and eigenvectors (as columns) of a symmetric matrix, by Jacobi rotations.
    static func eigen(_ matrix: [[Double]]) -> ([Double], [[Double]]) {
        let n = matrix.count
        var a = matrix
        var v = (0..<n).map { i in (0..<n).map { i == $0 ? 1.0 : 0.0 } }
        for _ in 0..<100 {
            var off = 0.0
            for i in 0..<n { for j in (i + 1)..<max(n, i + 1) { off += a[i][j] * a[i][j] } }
            if off < 1e-22 { break }
            for p in 0..<n {
                for q in (p + 1)..<max(n, p + 1) where abs(a[p][q]) > 1e-300 {
                    let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
                    let t = (theta >= 0 ? 1 : -1) / (abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot(), s = t * c
                    for k in 0..<n {
                        let akp = a[k][p], akq = a[k][q]
                        a[k][p] = c * akp - s * akq
                        a[k][q] = s * akp + c * akq
                    }
                    for k in 0..<n {
                        let apk = a[p][k], aqk = a[q][k]
                        a[p][k] = c * apk - s * aqk
                        a[q][k] = s * apk + c * aqk
                    }
                    for k in 0..<n {
                        let vkp = v[k][p], vkq = v[k][q]
                        v[k][p] = c * vkp - s * vkq
                        v[k][q] = s * vkp + c * vkq
                    }
                }
            }
        }
        return ((0..<n).map { a[$0][$0] }, v)
    }
}
