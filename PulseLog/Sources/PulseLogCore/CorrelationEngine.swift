import Foundation

/// A statement the app is willing to make about the user's own data.
public struct Insight: Identifiable, Sendable {
    public let id = UUID()
    public let headline: String
    public let detail: String
    /// How many paired observations it rests on, shown so the user can judge it.
    public let sampleCount: Int
    public let symbolName: String
}

/// Derives insights from the reading history.
///
/// This is the feature the incumbent apps do not have: they store readings and
/// draw them on a chart. The value in a year of measurements is in what varies
/// with what, and that is a statistics problem rather than a charting one.
///
/// Every claim here is gated on evidence. The engine would rather say nothing
/// than assert a relationship it cannot support — a fabricated correlation
/// about someone's heart is worse than an empty screen.
public enum CorrelationEngine {

    /// Minimum paired observations before any relationship is reported.
    /// Below this, sampling noise routinely produces large spurious
    /// correlations.
    public static let minimumPairs = 10

    public static func insights(heartRates: [HeartRateReading],
                                bloodPressures: [BloodPressureReading],
                                context: [DailyContext],
                                calendar: Calendar = .current) -> [Insight] {
        var results: [Insight] = []
        results.append(contentsOf: sleepInsight(heartRates, context, calendar))
        results.append(contentsOf: tagInsights(heartRates))
        results.append(contentsOf: timeOfDayBloodPressure(bloodPressures, calendar))
        results.append(contentsOf: activityInsight(heartRates, context, calendar))
        return results
    }

    // MARK: - Sleep vs resting heart rate

    static func sleepInsight(_ readings: [HeartRateReading],
                             _ context: [DailyContext],
                             _ calendar: Calendar) -> [Insight] {
        let sleepByDay = Dictionary(
            context.compactMap { entry -> (Date, Double)? in
                guard let hours = entry.sleepHours else { return nil }
                return (calendar.startOfDay(for: entry.date), hours)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var sleep: [Double] = [], bpm: [Double] = []
        for reading in readings where reading.isResting {
            let day = calendar.startOfDay(for: reading.date)
            guard let hours = sleepByDay[day] else { continue }
            sleep.append(hours)
            bpm.append(reading.bpm)
        }
        guard sleep.count >= minimumPairs,
              let correlation = Statistics.correlation(sleep, bpm),
              correlation.isSignificant else { return [] }

        // Report the effect in the units the user thinks in, not as an r value.
        let shortNights = zip(sleep, bpm).filter { $0.0 < 6.0 }.map(\.1)
        let longNights = zip(sleep, bpm).filter { $0.0 >= 7.0 }.map(\.1)

        if let difference = Statistics.groupDifference(shortNights, longNights),
           difference.isSignificant {
            let delta = abs(difference.difference)
            let direction = difference.difference > 0 ? "higher" : "lower"
            return [Insight(
                headline: String(format: "Short sleep tracks with a %.0f BPM %@ resting heart rate",
                                 delta, direction),
                detail: String(format: "On days after fewer than 6 hours of sleep your resting "
                               + "heart rate averaged %.0f BPM, against %.0f BPM after 7 hours "
                               + "or more.", Statistics.mean(shortNights), Statistics.mean(longNights)),
                sampleCount: difference.countA + difference.countB,
                symbolName: "bed.double"
            )]
        }

        let direction = correlation.r < 0 ? "lower" : "higher"
        return [Insight(
            headline: "More sleep tracks with a \(direction) resting heart rate",
            detail: String(format: "Across %d readings paired with sleep data, the relationship "
                           + "is consistent enough to be visible above day-to-day noise.",
                           correlation.n),
            sampleCount: correlation.n,
            symbolName: "bed.double"
        )]
    }

    // MARK: - Context tags

    static func tagInsights(_ readings: [HeartRateReading]) -> [Insight] {
        let resting = readings.filter { $0.tag == .resting }.map(\.bpm)
        guard resting.count >= minimumPairs else { return [] }

        var results: [Insight] = []
        for tag in [ContextTag.afterCaffeine, .stressed, .unwell] {
            let tagged = readings.filter { $0.tag == tag }.map(\.bpm)
            guard tagged.count >= 5,
                  let difference = Statistics.groupDifference(tagged, resting),
                  difference.isSignificant else { continue }

            let delta = abs(difference.difference)
            let direction = difference.difference > 0 ? "higher" : "lower"
            results.append(Insight(
                headline: String(format: "%@ readings run %.0f BPM %@",
                                 tag.displayName, delta, direction),
                detail: String(format: "%d readings tagged \"%@\" averaged %.0f BPM, against "
                               + "%.0f BPM across %d resting readings.",
                               tagged.count, tag.displayName.lowercased(),
                               Statistics.mean(tagged), Statistics.mean(resting), resting.count),
                sampleCount: tagged.count + resting.count,
                symbolName: tag.symbolName
            ))
        }
        return results
    }

    // MARK: - Time of day

    /// Morning against evening blood pressure.
    ///
    /// Clinically meaningful: blood pressure follows a daily rhythm, so
    /// comparing a morning reading against an evening one taken weeks earlier
    /// is not a like-for-like comparison. Home-monitoring guidance asks for
    /// consistent timing precisely because of this.
    static func timeOfDayBloodPressure(_ readings: [BloodPressureReading],
                                       _ calendar: Calendar) -> [Insight] {
        var morning: [Double] = [], evening: [Double] = []
        for reading in readings {
            let hour = calendar.component(.hour, from: reading.date)
            if (4..<12).contains(hour) { morning.append(Double(reading.systolic)) }
            else if (17..<24).contains(hour) { evening.append(Double(reading.systolic)) }
        }
        guard morning.count >= 5, evening.count >= 5,
              morning.count + evening.count >= minimumPairs,
              let difference = Statistics.groupDifference(morning, evening),
              difference.isSignificant else { return [] }

        let delta = abs(difference.difference)
        let higher = difference.difference > 0 ? "morning" : "evening"
        return [Insight(
            headline: String(format: "Your %@ systolic runs about %.0f mmHg higher", higher, delta),
            detail: String(format: "Morning readings averaged %.0f mmHg across %d entries; "
                           + "evening averaged %.0f across %d. Measuring at a consistent time "
                           + "makes your trend easier to interpret.",
                           Statistics.mean(morning), morning.count,
                           Statistics.mean(evening), evening.count),
            sampleCount: morning.count + evening.count,
            symbolName: "clock"
        )]
    }

    // MARK: - Activity

    static func activityInsight(_ readings: [HeartRateReading],
                                _ context: [DailyContext],
                                _ calendar: Calendar) -> [Insight] {
        let stepsByDay = Dictionary(
            context.compactMap { entry -> (Date, Double)? in
                guard let steps = entry.steps else { return nil }
                return (calendar.startOfDay(for: entry.date), Double(steps))
            },
            uniquingKeysWith: { first, _ in first }
        )

        var steps: [Double] = [], bpm: [Double] = []
        for reading in readings where reading.isResting {
            let day = calendar.startOfDay(for: reading.date)
            guard let count = stepsByDay[day] else { continue }
            steps.append(count)
            bpm.append(reading.bpm)
        }
        guard steps.count >= minimumPairs,
              let correlation = Statistics.correlation(steps, bpm),
              correlation.isSignificant else { return [] }

        let direction = correlation.r < 0 ? "lower" : "higher"
        return [Insight(
            headline: "More active days track with a \(direction) resting heart rate",
            detail: String(format: "Based on %d resting readings paired with that day's step "
                           + "count. This is an association in your own data, not a cause.",
                           correlation.n),
            sampleCount: correlation.n,
            symbolName: "figure.walk"
        )]
    }
}
