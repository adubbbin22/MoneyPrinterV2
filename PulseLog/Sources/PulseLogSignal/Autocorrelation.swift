import Foundation

public enum Autocorrelation {
    /// Normalised linear autocorrelation, mean removed, scaled so lag 0 is 1.
    ///
    /// Computed directly rather than through the FFT. At a 30 s record and
    /// 30 fps this is ~400k multiply-adds once per measurement, which is
    /// negligible, and the direct form has no zero-padding subtleties to get
    /// wrong.
    public static func compute(_ x: [Double]) -> [Double] {
        let n = x.count
        guard n > 0 else { return [] }

        let mean = x.reduce(0, +) / Double(n)
        let centred = x.map { $0 - mean }

        var energy = 0.0
        for v in centred { energy += v * v }
        guard energy > 0 else { return [Double](repeating: 0, count: n) }

        var acf = [Double](repeating: 0, count: n)
        centred.withUnsafeBufferPointer { buf in
            for lag in 0..<n {
                var sum = 0.0
                for i in 0..<(n - lag) {
                    sum += buf[i] * buf[i + lag]
                }
                acf[lag] = sum / energy
            }
        }
        return acf
    }

    /// Sub-sample peak location by fitting a parabola through three points.
    ///
    /// At 30 fps and 180 BPM the period is only 10 samples, so whole-sample
    /// quantisation is worth roughly 18 BPM. This interpolation is what makes
    /// a 30 fps camera usable at high heart rates at all.
    public static func parabolicRefine(_ values: [Double], index: Int) -> Double {
        guard index > 0, index < values.count - 1 else { return Double(index) }
        let a = values[index - 1], b = values[index], c = values[index + 1]
        let denom = a - 2.0 * b + c
        guard abs(denom) >= 1e-12 else { return Double(index) }
        let delta = 0.5 * (a - c) / denom
        guard delta > -1.0, delta < 1.0 else { return Double(index) }
        return Double(index) + delta
    }
}
