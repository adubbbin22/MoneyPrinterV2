import Foundation

/// Reference ranges for resting heart rate.
///
/// Resting heart rate for healthy adults spans roughly 60-100 BPM, with
/// trained athletes routinely lower. Age dependence is weak in adults, so the
/// bands below do not pretend to a precision the evidence does not support.
public enum HeartRateNorms {

    public enum Band: String, Sendable {
        case low, normal, elevated, high

        public var displayName: String {
            switch self {
            case .low:      return "Below typical"
            case .normal:   return "Typical"
            case .elevated: return "Above typical"
            case .high:     return "High"
            }
        }
    }

    /// Classify a *resting* rate. Meaningless for a reading taken after
    /// exertion, which is why callers pass the context tag.
    public static func classifyResting(bpm: Double) -> Band {
        switch bpm {
        case ..<50:    return .low
        case 50..<90:  return .normal
        case 90..<100: return .elevated
        default:       return .high
        }
    }

    /// A plain-language note, or nil when there is nothing useful to say.
    public static func note(for bpm: Double, isResting: Bool) -> String? {
        guard isResting else { return nil }
        switch classifyResting(bpm: bpm) {
        case .low:
            return "Below the usual resting range. Common in trained athletes; "
                 + "worth mentioning to a doctor if you also feel lightheaded."
        case .normal:
            return nil
        case .elevated:
            return "Slightly above the usual resting range. Caffeine, stress, "
                 + "poor sleep and illness all raise resting heart rate."
        case .high:
            return "Above the usual resting range. If it stays here at rest "
                 + "across several days, mention it to your doctor."
        }
    }
}
