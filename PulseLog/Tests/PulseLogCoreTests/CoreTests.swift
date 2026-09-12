import XCTest
@testable import PulseLogCore

final class BloodPressureCategoryTests: XCTestCase {

    func testGuidelineBoundaries() {
        let cases: [(Int, Int, BloodPressureCategory)] = [
            (119,  79, .normal),
            (120,  79, .elevated),
            (129,  79, .elevated),
            (130,  79, .stage1),
            (139,  89, .stage1),
            (140,  89, .stage2),
            (179, 119, .stage2),
            (181, 100, .crisis),
            (150, 121, .crisis),
            ( 85,  55, .low),
        ]
        for (systolic, diastolic, expected) in cases {
            XCTAssertEqual(BloodPressureCategory.classify(systolic: systolic, diastolic: diastolic),
                           expected, "\(systolic)/\(diastolic)")
        }
    }

    /// Normal and Elevated need *both* numbers to qualify; Stage 1 and 2 need
    /// only one. Getting this wrong silently under-reports hypertension, so it
    /// is tested explicitly rather than left to the boundary sweep.
    func testHigherOfTheTwoNumbersDecidesTheCategory() {
        // Systolic is merely "elevated", but diastolic is in stage 1 range.
        XCTAssertEqual(BloodPressureCategory.classify(systolic: 125, diastolic: 85), .stage1)
        // Systolic normal, diastolic stage 2.
        XCTAssertEqual(BloodPressureCategory.classify(systolic: 118, diastolic: 95), .stage2)
        // Elevated requires diastolic below 80.
        XCTAssertEqual(BloodPressureCategory.classify(systolic: 122, diastolic: 78), .elevated)
        XCTAssertEqual(BloodPressureCategory.classify(systolic: 122, diastolic: 82), .stage1)
    }

    func testOnlyCrisisIsUrgent() {
        for category in BloodPressureCategory.allCases {
            XCTAssertEqual(category.requiresUrgentAttention, category == .crisis)
            XCTAssertEqual(category.urgentMessage != nil, category == .crisis)
        }
    }

    func testValidationCatchesMistypedEntries() {
        XCTAssertNil(BloodPressureValidation.validate(systolic: 120, diastolic: 80))
        XCTAssertEqual(BloodPressureValidation.validate(systolic: 80, diastolic: 120),
                       .diastolicNotBelowSystolic)
        XCTAssertEqual(BloodPressureValidation.validate(systolic: 400, diastolic: 80),
                       .systolicOutOfRange)
        XCTAssertEqual(BloodPressureValidation.validate(systolic: 120, diastolic: 115),
                       .implausiblyNarrowPulsePressure)
    }

    func testMeanArterialPressure() {
        let reading = BloodPressureReading(date: Date(), systolic: 120, diastolic: 80)
        XCTAssertEqual(reading.meanArterialPressure, 93.333, accuracy: 0.01)
    }
}

final class StatisticsTests: XCTestCase {

    func testPerfectCorrelations() {
        let xs = [1.0, 2, 3, 4, 5, 6, 7, 8]
        XCTAssertEqual(Statistics.correlation(xs, xs)?.r ?? 0, 1.0, accuracy: 1e-6)
        XCTAssertEqual(Statistics.correlation(xs, xs.map { -$0 })?.r ?? 0, -1.0, accuracy: 1e-6)
    }

    func testCorrelationAgainstAKnownValue() {
        // r for these two series is 0.8 to three decimals.
        let xs = [1.0, 2, 3, 4, 5]
        let ys = [2.0, 4, 5, 4, 5]
        XCTAssertEqual(Statistics.correlation(xs, ys)?.r ?? 0, 0.7746, accuracy: 1e-3)
    }

    func testConstantSeriesHasUndefinedCorrelation() {
        XCTAssertNil(Statistics.correlation([1, 1, 1, 1, 1], [1, 2, 3, 4, 5]))
    }

    /// A small sample must not produce a confident-looking interval. This is
    /// the guard that stops the app inventing health claims.
    func testSmallSamplesYieldWideIntervals() {
        let small = Statistics.correlation([1, 2, 3, 4, 5], [2, 1, 4, 3, 5])
        XCTAssertNotNil(small)
        XCTAssertFalse(small?.isSignificant ?? true,
                       "five noisy points were reported as a significant relationship")
    }

    func testLargeConsistentSampleIsSignificant() {
        let xs = (0..<40).map(Double.init)
        let ys = xs.map { $0 * 2.0 + (($0.truncatingRemainder(dividingBy: 3)) - 1) }
        XCTAssertTrue(Statistics.correlation(xs, ys)?.isSignificant ?? false)
    }

    func testGroupDifferenceDetectsAndRejects() {
        let a = [70.0, 72, 71, 69, 73, 70, 71, 72]
        let clearlyHigher = a.map { $0 + 15 }
        XCTAssertTrue(Statistics.groupDifference(clearlyHigher, a)?.isSignificant ?? false)

        // Same distribution: there is no difference to find.
        XCTAssertFalse(Statistics.groupDifference(a, a)?.isSignificant ?? true)
    }

    func testStandardDeviationIsBesselCorrected() {
        XCTAssertEqual(Statistics.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9]),
                       2.138, accuracy: 1e-3)
    }
}

final class CorrelationEngineTests: XCTestCase {

    private func reading(daysAgo: Int, bpm: Double, tag: ContextTag = .resting) -> HeartRateReading {
        HeartRateReading(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                         bpm: bpm, confidence: 0.8, tag: tag)
    }

    private func context(daysAgo: Int, sleep: Double) -> DailyContext {
        DailyContext(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                     sleepHours: sleep)
    }

    /// The engine must stay silent on thin data, however suggestive it looks.
    func testSaysNothingBelowTheEvidenceThreshold() {
        var readings: [HeartRateReading] = []
        var contexts: [DailyContext] = []
        for day in 0..<6 {
            let shortSleep = day % 2 == 0
            readings.append(reading(daysAgo: day, bpm: shortSleep ? 78 : 62))
            contexts.append(context(daysAgo: day, sleep: shortSleep ? 5.0 : 8.0))
        }
        let insights = CorrelationEngine.insights(heartRates: readings, bloodPressures: [],
                                                  context: contexts)
        XCTAssertTrue(insights.isEmpty,
                      "an insight was generated from only 6 observations")
    }

    func testReportsAStrongRelationshipOnceThereIsEnoughData() {
        var readings: [HeartRateReading] = []
        var contexts: [DailyContext] = []
        for day in 0..<30 {
            let shortSleep = day % 2 == 0
            // A large, consistent effect with a little noise.
            let bpm = (shortSleep ? 76.0 : 62.0) + Double(day % 3) - 1.0
            readings.append(reading(daysAgo: day, bpm: bpm))
            contexts.append(context(daysAgo: day, sleep: shortSleep ? 5.0 : 8.0))
        }
        let insights = CorrelationEngine.insights(heartRates: readings, bloodPressures: [],
                                                  context: contexts)
        XCTAssertFalse(insights.isEmpty)
        XCTAssertTrue(insights.allSatisfy { $0.sampleCount >= CorrelationEngine.minimumPairs })
    }

    func testTagComparisonUsesRestingReadingsAsTheBaseline() {
        var readings: [HeartRateReading] = []
        for day in 0..<20 {
            readings.append(reading(daysAgo: day, bpm: 64 + Double(day % 3)))
        }
        for day in 0..<10 {
            readings.append(reading(daysAgo: day, bpm: 86 + Double(day % 3), tag: .afterCaffeine))
        }
        let insights = CorrelationEngine.insights(heartRates: readings, bloodPressures: [],
                                                  context: [])
        XCTAssertTrue(insights.contains { $0.headline.contains("After caffeine") },
                      "a large, well-sampled caffeine effect was not reported")
    }

    func testNoReadingsProducesNoInsights() {
        XCTAssertTrue(CorrelationEngine.insights(heartRates: [], bloodPressures: [],
                                                 context: []).isEmpty)
    }
}

final class HeartRateNormsTests: XCTestCase {

    func testRestingBands() {
        XCTAssertEqual(HeartRateNorms.classifyResting(bpm: 45), .low)
        XCTAssertEqual(HeartRateNorms.classifyResting(bpm: 70), .normal)
        XCTAssertEqual(HeartRateNorms.classifyResting(bpm: 95), .elevated)
        XCTAssertEqual(HeartRateNorms.classifyResting(bpm: 120), .high)
    }

    /// A rate taken after exercise carries no resting interpretation, so the
    /// app must not offer one.
    func testNoNoteForNonRestingReadings() {
        XCTAssertNil(HeartRateNorms.note(for: 150, isResting: false))
        XCTAssertNotNil(HeartRateNorms.note(for: 150, isResting: true))
        XCTAssertNil(HeartRateNorms.note(for: 70, isResting: true))
    }
}
