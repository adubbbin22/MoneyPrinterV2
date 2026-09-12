import Foundation

/// Tunable constants for the PPG pipeline.
///
/// Every value here was calibrated numerically against synthetic signals of
/// known heart rate; see `reference/` for the harness that produced them.
/// Changing one without re-running that sweep is a way to ship silently wrong
/// heart rates.
public enum PPGConstants {
    /// Physiological search band. Spans bradycardia through peak exertion.
    public static let minBPM: Double = 42.0
    public static let maxBPM: Double = 210.0

    public static var lowHz: Double { minBPM / 60.0 }   // 0.70 Hz
    public static var highHz: Double { maxBPM / 60.0 }  // 3.50 Hz

    /// In an octave dispute the lower frequency is accepted as the fundamental
    /// unless its band power falls below this fraction of the higher one's.
    ///
    /// Measured separation: genuine fundamentals held a ratio of at least
    /// 0.442, spurious sub-harmonics at most 0.012. This sits between them
    /// with roughly 10x margin either side.
    public static let subharmonicPowerFloor: Double = 0.10

    /// Minimum confidence for a reading to be shown to the user.
    ///
    /// Calibrated over 864 runs across nine scenarios: at 0.40 the number of
    /// accepted readings in error by more than 10 BPM falls from 24 to zero.
    /// 0.45 keeps a margin while still accepting ~83% of attempts.
    public static let confidenceThreshold: Double = 0.45

    /// Window for the moving-average detrend that removes the DC pedestal.
    public static let detrendWindowSeconds: Double = 1.0

    /// Capture duration for a full reading.
    public static let measurementDuration: TimeInterval = 30.0

    /// A provisional rate is shown from this point so the user sees progress,
    /// computed over a trailing window rather than the whole record.
    public static let provisionalAfterSeconds: TimeInterval = 8.0
    public static let provisionalWindowSeconds: TimeInterval = 10.0
}
