import Foundation

public enum Resampler {
    /// Linearly resample onto a uniform grid at the median observed rate.
    ///
    /// Camera frame delivery is not isochronous: `AVCaptureSession` delays and
    /// drops frames under thermal and exposure pressure. Treating jittered
    /// samples as though they were uniform smears the spectrum and biases the
    /// estimate, so this step is not optional.
    ///
    /// - Returns: the inferred sample rate, and the resampled values. A sample
    ///   rate of zero means the input was unusable.
    public static func uniform(timestamps: [Double], values: [Double]) -> (fs: Double, samples: [Double]) {
        guard timestamps.count == values.count, timestamps.count >= 2 else {
            return (0, values)
        }

        var deltas = [Double]()
        deltas.reserveCapacity(timestamps.count - 1)
        for i in 1..<timestamps.count {
            deltas.append(timestamps[i] - timestamps[i - 1])
        }
        let medianDt = median(deltas)
        guard medianDt > 0 else { return (0, values) }

        let fs = 1.0 / medianDt
        let span = timestamps[timestamps.count - 1] - timestamps[0]
        let count = Int(floor(span / medianDt)) + 1
        guard count >= 2 else { return (0, values) }

        var out = [Double]()
        out.reserveCapacity(count)
        let t0 = timestamps[0]

        // Both the grid and the source timestamps are ascending, so a single
        // advancing cursor is enough; no binary search per sample.
        var cursor = 0
        for i in 0..<count {
            let t = t0 + Double(i) * medianDt
            while cursor + 2 < timestamps.count && timestamps[cursor + 1] < t {
                cursor += 1
            }
            let t1 = timestamps[cursor], t2 = timestamps[cursor + 1]
            let v1 = values[cursor], v2 = values[cursor + 1]
            if t <= t1 {
                out.append(v1)
            } else if t >= t2 {
                out.append(v2)
            } else {
                let alpha = (t - t1) / (t2 - t1)
                out.append(v1 + alpha * (v2 - v1))
            }
        }
        return (fs, out)
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
