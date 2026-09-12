import Foundation

/// Blood-pressure categories per the 2017 ACC/AHA guideline.
///
/// These are thresholds for a *journal*: PulseLog never measures blood
/// pressure, it records what the user's cuff reported. Classification exists
/// to make a logged number legible, not to diagnose anything.
public enum BloodPressureCategory: String, CaseIterable, Sendable {
    case low
    case normal
    case elevated
    case stage1
    case stage2
    case crisis

    public var displayName: String {
        switch self {
        case .low:      return "Low"
        case .normal:   return "Normal"
        case .elevated: return "Elevated"
        case .stage1:   return "Stage 1"
        case .stage2:   return "Stage 2"
        case .crisis:   return "Crisis"
        }
    }

    /// Longer description shown beneath a reading.
    public var detail: String {
        switch self {
        case .low:
            return "Lower than the typical range. Worth mentioning to your "
                 + "doctor if you also feel dizzy or faint."
        case .normal:
            return "Within the range the American Heart Association considers normal."
        case .elevated:
            return "Above the normal range but not yet high blood pressure."
        case .stage1:
            return "Stage 1 hypertension range."
        case .stage2:
            return "Stage 2 hypertension range."
        case .crisis:
            return "This is in the hypertensive-crisis range."
        }
    }

    /// Whether a reading in this category warrants immediate medical attention.
    public var requiresUrgentAttention: Bool { self == .crisis }

    public var urgentMessage: String? {
        guard self == .crisis else { return nil }
        return "If you measured this correctly and are also experiencing chest "
             + "pain, shortness of breath, weakness, or trouble speaking or "
             + "seeing, call emergency services now. Otherwise wait five "
             + "minutes and measure again — if it is still this high, contact "
             + "your doctor immediately."
    }

    /// Classify a cuff reading.
    ///
    /// Two details of the guideline are easy to get wrong and are handled
    /// explicitly:
    ///
    /// 1. Normal and Elevated require *both* numbers to qualify, while Stage 1
    ///    and Stage 2 need only *one*. So 125/85 is Stage 1, not Elevated —
    ///    the diastolic value decides it.
    /// 2. When the two numbers fall in different categories, the higher one
    ///    applies. Evaluating from most to least severe gives that for free.
    public static func classify(systolic: Int, diastolic: Int) -> BloodPressureCategory {
        if systolic > 180 || diastolic > 120 { return .crisis }
        if systolic >= 140 || diastolic >= 90 { return .stage2 }
        if systolic >= 130 || diastolic >= 80 { return .stage1 }
        if systolic >= 120 { return .elevated }          // diastolic < 80 here
        if systolic < 90 || diastolic < 60 { return .low }
        return .normal
    }
}

/// A plausibility check on manual entry. Catches transposed or mistyped
/// numbers before they pollute the record.
public enum BloodPressureValidation {
    public static let systolicRange = 50...260
    public static let diastolicRange = 30...200

    public enum Problem: Equatable {
        case systolicOutOfRange
        case diastolicOutOfRange
        case diastolicNotBelowSystolic
        case implausiblyNarrowPulsePressure

        public var message: String {
            switch self {
            case .systolicOutOfRange:
                return "Systolic should be between 50 and 260."
            case .diastolicOutOfRange:
                return "Diastolic should be between 30 and 200."
            case .diastolicNotBelowSystolic:
                return "The top number should be higher than the bottom one."
            case .implausiblyNarrowPulsePressure:
                return "Those numbers are unusually close together. Double-check them."
            }
        }
    }

    public static func validate(systolic: Int, diastolic: Int) -> Problem? {
        guard systolicRange.contains(systolic) else { return .systolicOutOfRange }
        guard diastolicRange.contains(diastolic) else { return .diastolicOutOfRange }
        guard systolic > diastolic else { return .diastolicNotBelowSystolic }
        guard systolic - diastolic >= 10 else { return .implausiblyNarrowPulsePressure }
        return nil
    }
}
