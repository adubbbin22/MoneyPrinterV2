import Foundation

/// Small statistics helpers used by the insight engine.
///
/// Every function here returns an interval alongside its estimate. That is
/// deliberate: the app tells people things about their own health data, and a
/// correlation computed from nine readings is indistinguishable from noise.
/// Carrying the uncertainty makes it possible to stay quiet when the data does
/// not support a claim.
public enum Statistics {

    public static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (Bessel-corrected).
    public static func standardDeviation(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs)
        let sumSquares = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (sumSquares / Double(xs.count - 1)).squareRoot()
    }

    public static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    public struct Correlation {
        public let r: Double
        public let n: Int
        /// 95% confidence interval for r, via the Fisher z-transform.
        public let lower: Double
        public let upper: Double

        /// True when the interval excludes zero, i.e. the sign of the
        /// relationship is resolved by the data.
        public var isSignificant: Bool { (lower > 0 && upper > 0) || (lower < 0 && upper < 0) }
    }

    /// Pearson correlation with a 95% interval.
    ///
    /// Returns nil when there are too few pairs or either series is constant,
    /// in which case r is undefined rather than zero.
    public static func correlation(_ xs: [Double], _ ys: [Double]) -> Correlation? {
        guard xs.count == ys.count, xs.count >= 4 else { return nil }
        let n = xs.count
        let mx = mean(xs), my = mean(ys)

        var numerator = 0.0, sumX = 0.0, sumY = 0.0
        for i in 0..<n {
            let dx = xs[i] - mx, dy = ys[i] - my
            numerator += dx * dy
            sumX += dx * dx
            sumY += dy * dy
        }
        guard sumX > 0, sumY > 0 else { return nil }

        let r = max(-0.999999, min(0.999999, numerator / (sumX * sumY).squareRoot()))
        guard n > 3 else {
            return Correlation(r: r, n: n, lower: -1, upper: 1)
        }

        // Fisher z-transform: atanh(r) is approximately normal with standard
        // error 1/sqrt(n-3), which makes an interval straightforward.
        let z = atanh(r)
        let standardError = 1.0 / Double(n - 3).squareRoot()
        let margin = 1.96 * standardError
        return Correlation(r: r, n: n,
                           lower: tanh(z - margin), upper: tanh(z + margin))
    }

    public struct GroupDifference {
        public let difference: Double     // meanA - meanB
        public let countA: Int
        public let countB: Int
        public let lower: Double
        public let upper: Double

        public var isSignificant: Bool {
            (lower > 0 && upper > 0) || (lower < 0 && upper < 0)
        }
    }

    /// Difference in means with a 95% interval, using Welch's standard error
    /// so the two groups need not have equal variance or size.
    public static func groupDifference(_ a: [Double], _ b: [Double]) -> GroupDifference? {
        guard a.count >= 3, b.count >= 3 else { return nil }
        let sa = standardDeviation(a), sb = standardDeviation(b)
        let varianceTerm = (sa * sa) / Double(a.count) + (sb * sb) / Double(b.count)
        guard varianceTerm > 0 else { return nil }

        let difference = mean(a) - mean(b)
        let margin = 1.96 * varianceTerm.squareRoot()
        return GroupDifference(difference: difference,
                               countA: a.count, countB: b.count,
                               lower: difference - margin, upper: difference + margin)
    }
}
