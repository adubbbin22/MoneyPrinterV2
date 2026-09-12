import Foundation

/// The outcome of analysing a window of PPG samples.
public struct PPGResult: Equatable {
    public let bpm: Double?
    public let confidence: Double
    public let rmssdMs: Double?
    public let sampleRate: Double
    public let beatCount: Int
    /// True when the two estimators disagreed by an octave and the winner was
    /// decided on spectral evidence rather than native agreement.
    public let octaveResolved: Bool

    /// Whether this reading may be shown to the user.
    ///
    /// The product promise is that a displayed number is trustworthy, so a
    /// reading below the calibrated threshold is a retake, not a result.
    public var isReportable: Bool {
        bpm != nil && confidence >= PPGConstants.confidenceThreshold
    }

    static let unusable = PPGResult(bpm: nil, confidence: 0, rmssdMs: nil,
                                    sampleRate: 0, beatCount: 0, octaveResolved: false)
}

public enum PPGAnalyzer {

    /// Run the full pipeline over raw frame samples.
    ///
    /// - Parameters:
    ///   - timestamps: frame presentation times in seconds, ascending.
    ///   - values: mean red-channel intensity per frame, normalised to 0...1.
    public static func analyze(timestamps: [Double], values: [Double]) -> PPGResult {
        let (fs, uniform) = Resampler.uniform(timestamps: timestamps, values: values)
        guard fs > 0, uniform.count >= 16 else { return .unusable }

        let detrended = Filters.movingAverageDetrend(uniform, fs: fs)
        let filtered = Filters.bandpass(detrended, fs: fs)

        let autocorrelation = HeartRateEstimator.fromAutocorrelation(filtered, fs: fs)
        let spectral = HeartRateEstimator.fromSpectrum(filtered, fs: fs)

        // Autocorrelation leads: it degrades more gracefully on short records
        // than a periodogram, whose resolution is bounded by 1/T.
        guard var bpm = autocorrelation?.bpm ?? spectral?.bpm else { return .unusable }

        // Octave arbitration. If the two estimators sit in a ~2:1 or ~3:1
        // relationship, one has locked onto a harmonic or a sub-harmonic.
        //
        // The naive rule "more band power wins" is WRONG for PPG: the dicrotic
        // notch routinely makes the second harmonic stronger than the
        // fundamental, so that rule reports double rate for every bradycardic
        // subject. The sound principle is that a harmonic cannot exist without
        // its fundamental — so prefer the lower frequency, and reject it only
        // when it carries essentially no energy, which is the signature of the
        // autocorrelation having locked onto 2T rather than T.
        var octaveResolved = false
        if let ac = autocorrelation?.bpm, let fft = spectral?.bpm {
            let ratio = max(ac, fft) / min(ac, fft)
            if abs(ratio - 2.0) < 0.25 || abs(ratio - 3.0) < 0.30 {
                let lower = min(ac, fft), higher = max(ac, fft)
                let powerLow = HeartRateEstimator.bandPower(filtered, fs: fs, bpm: lower)
                let powerHigh = HeartRateEstimator.bandPower(filtered, fs: fs, bpm: higher)
                let lowerIsFundamental = powerHigh <= 0
                    || powerLow / powerHigh >= PPGConstants.subharmonicPowerFloor
                bpm = lowerIsFundamental ? lower : higher
                octaveResolved = true
            }
        }

        // Agreement between two independent estimators is the strongest
        // available evidence that the periodicity is real rather than artifact.
        var agreement = 0.0
        if let ac = autocorrelation?.bpm, let fft = spectral?.bpm {
            let disagreement = abs(ac - fft) / max(ac, fft)
            agreement = max(0.0, 1.0 - disagreement / 0.10)
            if octaveResolved {
                // A winner picked on spectral evidence is weaker grounds than
                // native agreement, so the reading is capped rather than credited.
                agreement = min(agreement, 0.40)
            }
        }

        let strength = max(0.0, autocorrelation?.strength ?? 0.0)
        let purity = spectral?.purity ?? 0.0
        let confidence = min(1.0, max(0.0,
            0.55 * strength + 0.25 * agreement + 0.20 * min(1.0, purity * 8.0)))

        let peaks = PeakDetector.detect(filtered, fs: fs, expectedBPM: bpm)
        let rmssd = HRV.rmssd(peaks: peaks, fs: fs)

        return PPGResult(bpm: bpm, confidence: confidence, rmssdMs: rmssd,
                         sampleRate: fs, beatCount: peaks.count,
                         octaveResolved: octaveResolved)
    }
}
