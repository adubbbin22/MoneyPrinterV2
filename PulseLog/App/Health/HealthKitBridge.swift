import Foundation
import HealthKit
import PulseLogCore

/// Reads context from HealthKit and writes readings back to it.
///
/// Writing matters as much as reading: a heart rate recorded here should show
/// up in Health alongside everything else, so PulseLog is one more source
/// rather than a silo the user has to remember to check.
@MainActor
final class HealthKitBridge: ObservableObject {

    private let store = HKHealthStore()
    @Published private(set) var isAuthorized = false

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let systolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
           let diastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(systolic); types.insert(diastolic)
        }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Writing

    func save(_ reading: HeartRateReading) async {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: reading.bpm),
            start: reading.date, end: reading.date,
            metadata: [HKMetadataKeyHeartRateMotionContext:
                        NSNumber(value: HKHeartRateMotionContext.sedentary.rawValue)]
        )
        try? await store.save(sample)
    }

    func save(_ reading: BloodPressureReading) async {
        guard let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
              let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure)
        else { return }

        let unit = HKUnit.millimeterOfMercury()
        let systolic = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: unit, doubleValue: Double(reading.systolic)),
            start: reading.date, end: reading.date)
        let diastolic = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: unit, doubleValue: Double(reading.diastolic)),
            start: reading.date, end: reading.date)

        // Health expects the pair as a correlation, not two loose samples.
        let correlation = HKCorrelation(type: correlationType, start: reading.date,
                                        end: reading.date, objects: [systolic, diastolic])
        try? await store.save(correlation)
    }

    // MARK: - Reading context

    /// Daily sleep, steps and workout minutes for the correlation engine.
    func dailyContext(days: Int, calendar: Calendar = .current) async -> [DailyContext] {
        guard HKHealthStore.isHealthDataAvailable(), isAuthorized else { return [] }
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))
        else { return [] }

        async let sleep = sleepHoursByDay(from: start, calendar: calendar)
        async let steps = stepsByDay(from: start, calendar: calendar)
        let (sleepByDay, stepsByDay) = await (sleep, steps)

        let allDays = Set(sleepByDay.keys).union(stepsByDay.keys)
        return allDays.map { day in
            DailyContext(date: day, sleepHours: sleepByDay[day], steps: stepsByDay[day])
        }
        .sorted { $0.date < $1.date }
    }

    private func sleepHoursByDay(from start: Date, calendar: Calendar) async -> [Date: Double] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        var totals: [Date: Double] = [:]
        for sample in samples {
            // Count only actual asleep states; "in bed" overstates sleep
            // substantially and would wash out any real relationship.
            let asleep: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            ]
            guard asleep.contains(sample.value) else { continue }

            // A night is attributed to the day it ends on, which is the day
            // whose readings it would plausibly affect.
            let day = calendar.startOfDay(for: sample.endDate)
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
            totals[day, default: 0] += hours
        }
        return totals
    }

    private func stepsByDay(from start: Date, calendar: Calendar) async -> [Date: Int] {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [:] }

        return await withCheckedContinuation { continuation in
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                options: .cumulativeSum,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var totals: [Date: Int] = [:]
                collection?.enumerateStatistics(from: start, to: Date()) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        totals[calendar.startOfDay(for: statistics.startDate)] =
                            Int(sum.doubleValue(for: .count()))
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }
}
