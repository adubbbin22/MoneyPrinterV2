import Foundation

public enum HeartRateEstimator {

    // MARK: - Autocorrelation

    public struct AutocorrelationEstimate {
        public let bpm: Double
        public let strength: Double
    }

    /// Dominant period from autocorrelation, guarding against octave errors.
    ///
    /// A periodic signal produces autocorrelation peaks at T, 2T, 3T ... and
    /// the dicrotic notch puts enough energy in the second harmonic that the
    /// 2T peak can be *taller* than the true T peak — measured at 200 BPM,
    /// acf(2T)=0.628 against acf(T)=0.598. Taking the global maximum therefore
    /// reports half the true rate.
    ///
    /// So: find the global best lag, then explicitly probe its integer
    /// sub-multiples. If a genuine local maximum sits near one of them with
    /// correlation within `subharmonicTolerance` of the best, that shorter lag
    /// is the real fundamental and wins.
    public static func fromAutocorrelation(_ filtered: [Double], fs: Double,
                                           subharmonicTolerance: Double = 0.70) -> AutocorrelationEstimate? {
        let acf = Autocorrelation.compute(filtered)
        guard acf.count > 4 else { return nil }

        let minLag = max(2, Int(floor(fs * 60.0 / PPGConstants.maxBPM)))
        let maxLag = min(acf.count - 2, Int(ceil(fs * 60.0 / PPGConstants.minBPM)))
        guard maxLag > minLag else { return nil }

        var candidates = [Int]()
        for lag in minLag...maxLag where acf[lag] > acf[lag - 1] && acf[lag] >= acf[lag + 1] && acf[lag] > 0 {
            candidates.append(lag)
        }
        guard let bestLag = candidates.max(by: { acf[$0] < acf[$1] }) else { return nil }
        let bestValue = acf[bestLag]
        guard bestValue > 0 else { return nil }

        // Probe integer sub-multiples of the winning lag for the true fundamental.
        var chosen = bestLag
        for divisor in [4, 3, 2] {
            let target = Double(bestLag) / Double(divisor)
            guard target >= Double(minLag) else { continue }
            let near = candidates.filter { abs(Double($0) - target) <= 1.5 }
            guard let contender = near.max(by: { acf[$0] < acf[$1] }) else { continue }
            if acf[contender] >= bestValue * subharmonicTolerance {
                chosen = contender
                break
            }
        }

        let refined = Autocorrelation.parabolicRefine(acf, index: chosen)
        guard refined > 0 else { return nil }
        let bpm = 60.0 * fs / refined
        guard bpm >= PPGConstants.minBPM, bpm <= PPGConstants.maxBPM else { return nil }
        return AutocorrelationEstimate(bpm: bpm, strength: acf[chosen])
    }

    // MARK: - Spectral

    public struct SpectralEstimate {
        public let bpm: Double
        /// Share of in-band energy sitting in the winning bin.
        public let purity: Double
    }

    /// Dominant frequency from a Hann-windowed periodogram. Cross-check only:
    /// its resolution is bounded by the record length, so it is the weaker
    /// estimator on short captures.
    public static func fromSpectrum(_ filtered: [Double], fs: Double) -> SpectralEstimate? {
        let n = filtered.count
        guard n >= 8 else { return nil }

        let window = FFT.hann(n)
        let windowed = zip(filtered, window).map(*)
        let nfft = FFT.strictlyGreaterPowerOfTwo(4 * n - 1)
        let power = FFT.powerSpectrum(windowed, nfft: nfft)
        // The reference peak-picks on magnitude, not power.
        let magnitude = power.map { $0.squareRoot() }

        let df = fs / Double(nfft)
        var banded = [Double](repeating: 0, count: magnitude.count)
        for i in 0..<magnitude.count {
            let f = Double(i) * df
            if f >= PPGConstants.lowHz && f <= PPGConstants.highHz {
                banded[i] = magnitude[i]
            }
        }

        var peak = 0
        var peakValue = 0.0
        for i in 0..<banded.count where banded[i] > peakValue {
            peakValue = banded[i]; peak = i
        }
        guard peakValue > 0 else { return nil }

        let refined = Autocorrelation.parabolicRefine(banded, index: peak)
        let bpm = refined * df * 60.0
        guard bpm >= PPGConstants.minBPM, bpm <= PPGConstants.maxBPM else { return nil }

        let total = banded.reduce(0, +)
        let purity = total > 0 ? peakValue / total : 0
        return SpectralEstimate(bpm: bpm, purity: purity)
    }

    /// Periodogram power within a narrow band around `bpm`.
    ///
    /// Used to arbitrate octave disputes: a spurious sub-harmonic has no
    /// independent existence in the spectrum, so it carries almost no energy.
    public static func bandPower(_ filtered: [Double], fs: Double, bpm: Double,
                                 relativeWidth: Double = 0.08) -> Double {
        let n = filtered.count
        guard n >= 8, bpm > 0 else { return 0 }

        let window = FFT.hann(n)
        let windowed = zip(filtered, window).map(*)
        let nfft = FFT.strictlyGreaterPowerOfTwo(4 * n - 1)
        let power = FFT.powerSpectrum(windowed, nfft: nfft)

        let df = fs / Double(nfft)
        let f0 = bpm / 60.0
        let lo = f0 * (1.0 - relativeWidth), hi = f0 * (1.0 + relativeWidth)

        var sum = 0.0
        for i in 0..<power.count {
            let f = Double(i) * df
            if f >= lo && f <= hi { sum += power[i] }
        }
        return sum
    }
}
