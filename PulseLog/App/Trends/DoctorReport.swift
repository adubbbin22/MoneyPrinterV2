import Charts
import PulseLogCore
import SwiftUI
import UIKit

/// Builds a one-page-per-section PDF summarising a date range.
///
/// This is the feature people show to a clinician, so it is built for that
/// reader: counts, averages and ranges first, the time-of-day split that
/// home-monitoring guidance actually asks about, the distribution across
/// categories, and only then the raw table. It states plainly where each
/// number came from, because a summary of unknown provenance is useless in
/// an appointment.
enum DoctorReport {

    struct Summary {
        let count: Int
        let mean: Double
        let min: Double
        let max: Double
        let standardDeviation: Double

        init?(_ values: [Double]) {
            guard !values.isEmpty, let low = values.min(), let high = values.max() else { return nil }
            count = values.count
            mean = Statistics.mean(values)
            min = low
            max = high
            standardDeviation = Statistics.standardDeviation(values)
        }
    }

    /// Marked `@MainActor` because it rasterises SwiftUI views through
    /// `ImageRenderer`, and because `UIGraphicsPDFRenderer` expects to run on
    /// the main thread. Callers reach it from a `.task`, which is already
    /// main-actor isolated.
    @MainActor
    static func render(heartRates: [HeartRateReading],
                       bloodPressures: [BloodPressureReading],
                       from startDate: Date, to endDate: Date,
                       calendar: Calendar = .current) -> Data {
        let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter, 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 56
            let margin: CGFloat = 48
            let width = pageSize.width - margin * 2

            y = drawTitle("PulseLog summary", at: y, margin: margin)
            y = drawText(dateRangeLine(startDate, endDate), at: y + 2, margin: margin,
                         width: width, font: .systemFont(ofSize: 11), color: .darkGray)
            y += 18

            // --- Blood pressure ------------------------------------------------
            if !bloodPressures.isEmpty {
                y = drawHeading("Blood pressure", at: y, margin: margin)
                y = drawText("Self-reported, entered manually from the patient's own cuff.",
                             at: y, margin: margin, width: width,
                             font: .italicSystemFont(ofSize: 9.5), color: .gray)
                y += 6

                if let systolic = Summary(bloodPressures.map { Double($0.systolic) }),
                   let diastolic = Summary(bloodPressures.map { Double($0.diastolic) }) {
                    y = drawStatLine("Systolic", systolic, unit: "mmHg", at: y, margin: margin)
                    y = drawStatLine("Diastolic", diastolic, unit: "mmHg", at: y, margin: margin)
                }
                y += 6

                y = drawSubheading("Time of day", at: y, margin: margin)
                let morning = bloodPressures.filter { (4..<12).contains(calendar.component(.hour, from: $0.date)) }
                let evening = bloodPressures.filter { (17..<24).contains(calendar.component(.hour, from: $0.date)) }
                y = drawText(timeOfDayLine("Morning (04:00–12:00)", morning), at: y,
                             margin: margin, width: width)
                y = drawText(timeOfDayLine("Evening (17:00–24:00)", evening), at: y,
                             margin: margin, width: width)
                y += 6

                y = drawSubheading("Distribution (ACC/AHA 2017)", at: y, margin: margin)
                for category in BloodPressureCategory.allCases {
                    let n = bloodPressures.filter { $0.category == category }.count
                    guard n > 0 else { continue }
                    let share = Double(n) / Double(bloodPressures.count) * 100
                    y = drawText(String(format: "  %@: %d readings (%.0f%%)",
                                        category.displayName, n, share),
                                 at: y, margin: margin, width: width)
                }
                y += 12
            }

            // --- Heart rate ----------------------------------------------------
            if !heartRates.isEmpty {
                y = drawHeading("Heart rate", at: y, margin: margin)
                y = drawText("Measured by phone camera photoplethysmography. "
                             + "Not a medical device; readings below the app's "
                             + "confidence threshold are discarded, not recorded.",
                             at: y, margin: margin, width: width,
                             font: .italicSystemFont(ofSize: 9.5), color: .gray)
                y += 6

                let resting = heartRates.filter(\.isResting)
                if let all = Summary(heartRates.map(\.bpm)) {
                    y = drawStatLine("All readings", all, unit: "BPM", at: y, margin: margin)
                }
                if let restingSummary = Summary(resting.map(\.bpm)) {
                    y = drawStatLine("Resting only", restingSummary, unit: "BPM", at: y, margin: margin)
                }
                let hrvValues = heartRates.compactMap(\.hrvMs)
                if let hrv = Summary(hrvValues) {
                    y = drawStatLine("HRV (RMSSD)", hrv, unit: "ms", at: y, margin: margin)
                }
                y += 12
            }

            // --- Chart ---------------------------------------------------------
            if let chart = chartImage(heartRates: heartRates, bloodPressures: bloodPressures,
                                      size: CGSize(width: width, height: 180)) {
                if y + 190 > pageSize.height - 60 {
                    context.beginPage(); y = 56
                }
                chart.draw(in: CGRect(x: margin, y: y, width: width, height: 180))
                y += 196
            }

            // --- Raw table -----------------------------------------------------
            y = startNewPageIfNeeded(context, y: y, needed: 120, pageHeight: pageSize.height)
            y = drawHeading("All readings", at: y, margin: margin)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"

            var rows: [(Date, String, String)] = []
            rows += bloodPressures.map {
                ($0.date, "BP", "\($0.systolic)/\($0.diastolic) mmHg · \($0.category.displayName) · \($0.tag.displayName)")
            }
            rows += heartRates.map {
                ($0.date, "HR", String(format: "%.0f BPM · %@", $0.bpm, $0.tag.displayName))
            }
            rows.sort { $0.0 < $1.0 }

            for row in rows {
                y = startNewPageIfNeeded(context, y: y, needed: 18, pageHeight: pageSize.height)
                let line = "\(formatter.string(from: row.0))   \(row.1)   \(row.2)"
                y = drawText(line, at: y, margin: margin, width: width,
                             font: .monospacedSystemFont(ofSize: 9, weight: .regular))
            }

            y = startNewPageIfNeeded(context, y: y, needed: 60, pageHeight: pageSize.height)
            y += 12
            _ = drawText("Generated by PulseLog. Heart-rate figures are from a consumer "
                         + "wellness app, not a medical device. Blood-pressure figures are "
                         + "self-reported from the patient's own cuff and were not observed "
                         + "by the app.",
                         at: y, margin: margin, width: width,
                         font: .italicSystemFont(ofSize: 8.5), color: .gray)
        }
    }

    // MARK: - Drawing helpers

    private static func startNewPageIfNeeded(_ context: UIGraphicsPDFRendererContext,
                                             y: CGFloat, needed: CGFloat,
                                             pageHeight: CGFloat) -> CGFloat {
        if y + needed > pageHeight - 48 {
            context.beginPage()
            return 56
        }
        return y
    }

    private static func dateRangeLine(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private static func timeOfDayLine(_ label: String, _ readings: [BloodPressureReading]) -> String {
        guard !readings.isEmpty else { return "  \(label): no readings" }
        let systolic = Statistics.mean(readings.map { Double($0.systolic) })
        let diastolic = Statistics.mean(readings.map { Double($0.diastolic) })
        return String(format: "  %@: %.0f/%.0f mmHg across %d readings",
                      label, systolic, diastolic, readings.count)
    }

    @discardableResult
    private static func drawTitle(_ text: String, at y: CGFloat, margin: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
        return y + 28
    }

    @discardableResult
    private static func drawHeading(_ text: String, at y: CGFloat, margin: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black,
        ]
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
        return y + 20
    }

    @discardableResult
    private static func drawSubheading(_ text: String, at y: CGFloat, margin: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.darkGray,
        ]
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
        return y + 16
    }

    @discardableResult
    private static func drawText(_ text: String, at y: CGFloat, margin: CGFloat, width: CGFloat,
                                 font: UIFont = .systemFont(ofSize: 11),
                                 color: UIColor = .black) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil
        )
        (text as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: bounds.height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attributes, context: nil)
        return y + bounds.height + 3
    }

    @discardableResult
    private static func drawStatLine(_ label: String, _ summary: Summary, unit: String,
                                     at y: CGFloat, margin: CGFloat) -> CGFloat {
        let text = String(format: "  %@: mean %.0f %@ (range %.0f–%.0f, SD %.1f, n=%d)",
                          label, summary.mean, unit, summary.min, summary.max,
                          summary.standardDeviation, summary.count)
        return drawText(text, at: y, margin: margin, width: 520,
                        font: .systemFont(ofSize: 11))
    }

    /// Rasterise the same chart the user sees in the app, rather than
    /// redrawing an approximation of it in Core Graphics.
    private static func chartImage(heartRates: [HeartRateReading],
                                   bloodPressures: [BloodPressureReading],
                                   size: CGSize) -> UIImage? {
        let chart = ReportChart(heartRates: heartRates, bloodPressures: bloodPressures)
            .frame(width: size.width, height: size.height)
            .background(Color.white)

        let renderer = ImageRenderer(content: chart)
        renderer.scale = 3.0   // printed output, so render well above screen density
        return renderer.uiImage
    }
}

/// Print-oriented chart: no interaction, high contrast, explicit legend.
struct ReportChart: View {
    let heartRates: [HeartRateReading]
    let bloodPressures: [BloodPressureReading]

    var body: some View {
        Chart {
            ForEach(bloodPressures) { reading in
                RuleMark(x: .value("Date", reading.date),
                         yStart: .value("Diastolic", reading.diastolic),
                         yEnd: .value("Systolic", reading.systolic))
                    .foregroundStyle(.black.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(heartRates) { reading in
                PointMark(x: .value("Date", reading.date),
                          y: .value("BPM", reading.bpm))
                    .foregroundStyle(.red.opacity(0.7))
                    .symbolSize(20)
            }
        }
        .chartYAxisLabel("mmHg / BPM")
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
    }
}
