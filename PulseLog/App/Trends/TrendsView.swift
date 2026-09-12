import Charts
import PulseLogCore
import SwiftData
import SwiftUI

struct TrendsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            }
        }
    }

    @Query(sort: \StoredHeartRateReading.date) private var heartRates: [StoredHeartRateReading]
    @Query(sort: \StoredBloodPressureReading.date) private var bloodPressures: [StoredBloodPressureReading]
    @State private var range: Range = .month
    @State private var showingReport = false

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -range.days, to: Date()) ?? .distantPast
    }

    private var hrValues: [HeartRateReading] {
        heartRates.map(\.value).filter { $0.date >= cutoff }
    }

    private var bpValues: [BloodPressureReading] {
        bloodPressures.map(\.value).filter { $0.date >= cutoff }
    }

    private var insights: [Insight] {
        CorrelationEngine.insights(heartRates: heartRates.map(\.value),
                                   bloodPressures: bloodPressures.map(\.value),
                                   context: [])   // supplied by HealthKit at runtime
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if hrValues.isEmpty && bpValues.isEmpty {
                        EmptyTrendsView()
                    } else {
                        if !hrValues.isEmpty { HeartRateChartCard(readings: hrValues) }
                        if !bpValues.isEmpty { BloodPressureChartCard(readings: bpValues) }
                        InsightsSection(insights: insights)
                    }
                }
                .padding()
            }
            .background(Theme.pageBackground)
            .navigationTitle("Trends")
            .toolbar {
                Button {
                    showingReport = true
                } label: {
                    Label("Doctor report", systemImage: "square.and.arrow.up")
                }
                .disabled(hrValues.isEmpty && bpValues.isEmpty)
            }
            .sheet(isPresented: $showingReport) {
                DoctorReportView(heartRates: hrValues, bloodPressures: bpValues,
                                 from: cutoff, to: Date())
            }
        }
    }
}

/// Heart-rate chart.
///
/// Plots a moving average over the individual points rather than joining raw
/// readings: a jagged line through single measurements exaggerates
/// variation that is mostly measurement noise, and hides the trend that
/// actually matters.
struct HeartRateChartCard: View {
    let readings: [HeartRateReading]

    private var smoothed: [(date: Date, bpm: Double)] {
        MovingAverage.over(readings.map { ($0.date, $0.bpm) }, window: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heart rate").font(.headline)
            SummaryRow(values: readings.map(\.bpm), unit: "BPM")

            Chart {
                ForEach(readings) { reading in
                    PointMark(x: .value("Date", reading.date),
                              y: .value("BPM", reading.bpm))
                        .foregroundStyle(Theme.accent.opacity(0.35))
                        .symbolSize(28)
                }
                ForEach(smoothed, id: \.date) { point in
                    LineMark(x: .value("Date", point.date),
                             y: .value("Average", point.bpm))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
            .chartYAxisLabel("BPM")
            .frame(height: 200)

            Text("Line shows a 5-reading moving average.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }
}

struct BloodPressureChartCard: View {
    let readings: [BloodPressureReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blood pressure").font(.headline)

            HStack(spacing: 20) {
                SummaryRow(values: readings.map { Double($0.systolic) }, unit: "systolic")
                SummaryRow(values: readings.map { Double($0.diastolic) }, unit: "diastolic")
            }

            Chart {
                ForEach(readings) { reading in
                    // A single reading is a range, not a point, so it is drawn
                    // as one. Two separate lines invite reading the gap wrong.
                    RuleMark(x: .value("Date", reading.date),
                             yStart: .value("Diastolic", reading.diastolic),
                             yEnd: .value("Systolic", reading.systolic))
                        .foregroundStyle(Theme.color(for: reading.category).opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
            .chartYAxisLabel("mmHg")
            .frame(height: 200)

            CategoryDistribution(readings: readings)
        }
        .card()
    }
}

struct CategoryDistribution: View {
    let readings: [BloodPressureReading]

    private var counts: [(BloodPressureCategory, Int)] {
        BloodPressureCategory.allCases.compactMap { category in
            let n = readings.filter { $0.category == category }.count
            return n > 0 ? (category, n) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Distribution").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(counts, id: \.0) { category, count in
                HStack {
                    Circle().fill(Theme.color(for: category)).frame(width: 8, height: 8)
                    Text(category.displayName).font(.caption)
                    Spacer()
                    Text("\(count) · \(percent(count))").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func percent(_ count: Int) -> String {
        guard !readings.isEmpty else { return "0%" }
        return "\(Int((Double(count) / Double(readings.count) * 100).rounded()))%"
    }
}

struct SummaryRow: View {
    let values: [Double]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f", Statistics.mean(values)))
                .font(.title2.weight(.semibold)).monospacedDigit()
            Text("avg \(unit) · \(values.count) readings")
                .font(.caption2).foregroundStyle(.secondary)
            if let low = values.min(), let high = values.max() {
                Text(String(format: "range %.0f–%.0f", low, high))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct InsightsSection: View {
    let insights: [Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What your data shows").font(.headline)

            if insights.isEmpty {
                // Saying nothing is the correct output when the data does not
                // support a claim, so the empty state explains itself rather
                // than looking like a failure.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing conclusive yet")
                        .font(.subheadline.weight(.medium))
                    Text("PulseLog looks for patterns that hold up across at least "
                         + "\(CorrelationEngine.minimumPairs) readings. Below that, "
                         + "apparent patterns are usually chance. Keep measuring and "
                         + "this section will fill in.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            } else {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.symbolName)
                            .font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.headline).font(.subheadline.weight(.semibold))
                            Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                            Text("Based on \(insight.sampleCount) readings")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
        }
    }
}

struct EmptyTrendsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No readings yet").font(.headline)
            Text("Measure your heart rate or log a blood pressure reading to start a trend.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

enum MovingAverage {
    /// Centred moving average over an ordered series.
    static func over(_ points: [(Date, Double)], window: Int) -> [(date: Date, bpm: Double)] {
        guard points.count >= window, window > 0 else {
            return points.map { (date: $0.0, bpm: $0.1) }
        }
        let half = window / 2
        return points.indices.map { i in
            let lower = max(0, i - half)
            let upper = min(points.count - 1, i + half)
            let slice = points[lower...upper].map(\.1)
            return (date: points[i].0, bpm: slice.reduce(0, +) / Double(slice.count))
        }
    }
}
