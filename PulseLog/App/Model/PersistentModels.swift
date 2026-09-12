import Foundation
import PulseLogCore
import SwiftData

/// SwiftData records.
///
/// These are storage types only. All interpretation — classification, norms,
/// correlation — lives in `PulseLogCore` against plain value types, so the
/// logic worth testing does not require a persistent container to exercise.
@Model
final class StoredHeartRateReading {
    @Attribute(.unique) var id: UUID
    var date: Date
    var bpm: Double
    var hrvMs: Double?
    var confidence: Double
    var tagRaw: String
    var note: String?

    init(id: UUID = UUID(), date: Date, bpm: Double, hrvMs: Double? = nil,
         confidence: Double, tag: ContextTag = .resting, note: String? = nil) {
        self.id = id; self.date = date; self.bpm = bpm; self.hrvMs = hrvMs
        self.confidence = confidence; self.tagRaw = tag.rawValue; self.note = note
    }

    var tag: ContextTag {
        get { ContextTag(rawValue: tagRaw) ?? .resting }
        set { tagRaw = newValue.rawValue }
    }

    var value: HeartRateReading {
        HeartRateReading(id: id, date: date, bpm: bpm, hrvMs: hrvMs,
                         confidence: confidence, tag: tag, note: note)
    }
}

@Model
final class StoredBloodPressureReading {
    @Attribute(.unique) var id: UUID
    var date: Date
    var systolic: Int
    var diastolic: Int
    var pulse: Int?
    var tagRaw: String
    var note: String?

    init(id: UUID = UUID(), date: Date, systolic: Int, diastolic: Int,
         pulse: Int? = nil, tag: ContextTag = .resting, note: String? = nil) {
        self.id = id; self.date = date; self.systolic = systolic
        self.diastolic = diastolic; self.pulse = pulse
        self.tagRaw = tag.rawValue; self.note = note
    }

    var tag: ContextTag {
        get { ContextTag(rawValue: tagRaw) ?? .resting }
        set { tagRaw = newValue.rawValue }
    }

    var value: BloodPressureReading {
        BloodPressureReading(id: id, date: date, systolic: systolic, diastolic: diastolic,
                             pulse: pulse, tag: tag, note: note)
    }
}

enum ModelStack {
    static let schema = Schema([StoredHeartRateReading.self, StoredBloodPressureReading.self])

    /// iCloud sync is a paid feature, so the container is built to match
    /// entitlement rather than always syncing.
    static func container(cloudSyncEnabled: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: cloudSyncEnabled ? .automatic : .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
