import Foundation

public enum PeakDetector {
    /// Peak picking with a refractory period derived from the estimated rate.
    ///
    /// The refractory period is 60% of the expected beat interval. No second
    /// systolic peak can physiologically occur that soon, so this is what stops
    /// the dicrotic notch from being counted as a beat and halving every RR
    /// interval.
    public static func detect(_ filtered: [Double], fs: Double, expectedBPM: Double) -> [Int] {
        guard filtered.count >= 3, expectedBPM > 0, fs > 0 else { return [] }

        let refractory = max(1, Int((0.6 * fs * 60.0 / expectedBPM).rounded()))
        let threshold = 0.3 * standardDeviation(filtered)

        var peaks = [Int]()
        var last = Int.min / 2
        for i in 1..<(filtered.count - 1) {
            let v = filtered[i]
            guard v > filtered[i - 1], v >= filtered[i + 1], v > threshold else { continue }
            if i - last >= refractory {
                peaks.append(i)
                last = i
            } else if let lastPeak = peaks.last, v > filtered[lastPeak] {
                // A taller peak inside the refractory window replaces the last.
                peaks[peaks.count - 1] = i
                last = i
            }
        }
        return peaks
    }

    static func standardDeviation(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let mean = x.reduce(0, +) / Double(x.count)
        let variance = x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(x.count)
        return variance.squareRoot()
    }
}

public enum HRV {

    /// Usable RR intervals in milliseconds, with implausible ones removed.
    static func intervals(peaks: [Int], fs: Double) -> [Double] {
        guard peaks.count >= 2, fs > 0 else { return [] }
        var out = [Double]()
        for i in 1..<peaks.count {
            let ms = Double(peaks[i] - peaks[i - 1]) / fs * 1000.0
            // Implausible intervals indicate a missed or spurious detection
            // rather than a real beat.
            if ms >= 250.0 && ms <= 2000.0 { out.append(ms) }
        }
        return out
    }

    /// Coefficient of variation of the RR intervals.
    ///
    /// Measures how well the "one dominant period" assumption actually fits.
    /// A steady pulse gives a few percent; a poorly-tracked or genuinely
    /// erratic one gives far more.
    ///
    /// Note this is *not* an irregular-rhythm detector, and must never be
    /// presented as one. Measured across the validation corpus, weak-perfusion
    /// captures produce higher dispersion (median 0.19) than genuinely high
    /// heart-rate variability does (0.10), because noisy peak detection and an
    /// irregular rhythm look alike here. Using it to tell someone their
    /// heartbeat is irregular would mostly flag cold fingers.
    public static func dispersion(peaks: [Int], fs: Double) -> Double? {
        let rr = intervals(peaks: peaks, fs: fs)
        guard rr.count >= 3 else { return nil }
        let mean = rr.reduce(0, +) / Double(rr.count)
        guard mean > 0 else { return nil }
        // Sample standard deviation, matching the reference.
        let sumSquares = rr.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let sd = (sumSquares / Double(rr.count - 1)).squareRoot()
        return sd / mean
    }

    /// Root mean square of successive RR-interval differences, in milliseconds.
    ///
    /// Returns nil when there are too few usable intervals — reporting an HRV
    /// figure from two beats would be noise dressed as a measurement.
    public static func rmssd(peaks: [Int], fs: Double) -> Double? {
        guard peaks.count >= 3, fs > 0 else { return nil }
        let rr = intervals(peaks: peaks, fs: fs)
        guard rr.count >= 2 else { return nil }

        var sumSquares = 0.0
        for i in 1..<rr.count {
            let d = rr[i] - rr[i - 1]
            sumSquares += d * d
        }
        return (sumSquares / Double(rr.count - 1)).squareRoot()
    }
}
