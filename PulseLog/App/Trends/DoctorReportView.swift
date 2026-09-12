import PulseLogCore
import SwiftUI
import UniformTypeIdentifiers

/// Preview and share sheet for the generated report.
struct DoctorReportView: View {
    let heartRates: [HeartRateReading]
    let bloodPressures: [BloodPressureReading]
    let from: Date
    let to: Date

    @Environment(\.dismiss) private var dismiss
    @State private var document: ReportDocument?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 52)).foregroundStyle(Theme.accent)

                Text("Summary for your doctor").font(.title3.weight(.semibold))

                Text("A PDF covering \(bloodPressures.count) blood pressure and "
                     + "\(heartRates.count) heart rate readings: averages, ranges, "
                     + "time-of-day breakdown, distribution across categories, and "
                     + "the full list.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let document {
                    ShareLink(item: document, preview: SharePreview("PulseLog summary")) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                } else {
                    ProgressView("Preparing…")
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let data = DoctorReport.render(heartRates: heartRates,
                                               bloodPressures: bloodPressures,
                                               from: from, to: to)
                document = ReportDocument(data: data)
            }
        }
    }
}

/// Wraps the PDF so `ShareLink` exports a real file with a sensible name.
struct ReportDocument: Transferable {
    let data: Data
    let filename: String

    init(data: Data, date: Date = Date()) {
        self.data = data
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.filename = "PulseLog-\(formatter.string(from: date)).pdf"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName("PulseLog summary.pdf")
    }
}
