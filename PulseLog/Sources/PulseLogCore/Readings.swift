import Foundation

/// What the user was doing when a reading was taken.
///
/// Context is not decoration: a heart rate of 110 means completely different
/// things after a run and at rest, and without the tag the trend line mixes
/// them into an average that describes neither.
public enum ContextTag: String, CaseIterable, Codable, Sendable {
    case resting
    case postExercise
    case stressed
    case afterCaffeine
    case unwell
    case medication

    public var displayName: String {
        switch self {
        case .resting:       return "Resting"
        case .postExercise:  return "After exercise"
        case .stressed:      return "Stressed"
        case .afterCaffeine: return "After caffeine"
        case .unwell:        return "Unwell"
        case .medication:    return "After medication"
        }
    }

    public var symbolName: String {
        switch self {
        case .resting:       return "figure.seated.side"
        case .postExercise:  return "figure.run"
        case .stressed:      return "bolt.heart"
        case .afterCaffeine: return "cup.and.saucer"
        case .unwell:        return "thermometer"
        case .medication:    return "pills"
        }
    }
}

public struct HeartRateReading: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let bpm: Double
    public let hrvMs: Double?
    public let confidence: Double
    public let tag: ContextTag
    public let note: String?

    public init(id: UUID = UUID(), date: Date, bpm: Double, hrvMs: Double? = nil,
                confidence: Double, tag: ContextTag = .resting, note: String? = nil) {
        self.id = id; self.date = date; self.bpm = bpm; self.hrvMs = hrvMs
        self.confidence = confidence; self.tag = tag; self.note = note
    }

    public var isResting: Bool { tag == .resting }
}

public struct BloodPressureReading: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let systolic: Int
    public let diastolic: Int
    public let pulse: Int?
    public let tag: ContextTag
    public let note: String?

    public init(id: UUID = UUID(), date: Date, systolic: Int, diastolic: Int,
                pulse: Int? = nil, tag: ContextTag = .resting, note: String? = nil) {
        self.id = id; self.date = date; self.systolic = systolic
        self.diastolic = diastolic; self.pulse = pulse; self.tag = tag; self.note = note
    }

    public var category: BloodPressureCategory {
        BloodPressureCategory.classify(systolic: systolic, diastolic: diastolic)
    }

    /// Mean arterial pressure, the perfusion-weighted average of the cycle.
    public var meanArterialPressure: Double {
        Double(diastolic) + Double(systolic - diastolic) / 3.0
    }
}

/// Per-day context pulled from HealthKit, used to explain trends.
public struct DailyContext: Codable, Sendable {
    public let date: Date
    public let sleepHours: Double?
    public let steps: Int?
    public let workoutMinutes: Int?

    public init(date: Date, sleepHours: Double? = nil, steps: Int? = nil,
                workoutMinutes: Int? = nil) {
        self.date = date; self.sleepHours = sleepHours
        self.steps = steps; self.workoutMinutes = workoutMinutes
    }
}
