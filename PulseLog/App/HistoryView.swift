import PulseLogCore
import SwiftData
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredHeartRateReading.date, order: .reverse)
    private var heartRates: [StoredHeartRateReading]
    @Query(sort: \StoredBloodPressureReading.date, order: .reverse)
    private var bloodPressures: [StoredBloodPressureReading]

    @State private var showingPaywall = false

    /// The free tier limits how far back history is *shown*, never what is
    /// recorded. Readings outside the window stay stored and reappear intact
    /// on subscribing — a health record that silently drops data would be
    /// worse than useless.
    private var cutoff: Date? {
        guard !subscriptions.isSubscribed else { return nil }
        return Calendar.current.date(byAdding: .day, value: -FreeTier.historyDays, to: Date())
    }

    private var visibleHeartRates: [StoredHeartRateReading] {
        guard let cutoff else { return heartRates }
        return heartRates.filter { $0.date >= cutoff }
    }

    private var visibleBloodPressures: [StoredBloodPressureReading] {
        guard let cutoff else { return bloodPressures }
        return bloodPressures.filter { $0.date >= cutoff }
    }

    private var hiddenCount: Int {
        (heartRates.count - visibleHeartRates.count)
            + (bloodPressures.count - visibleBloodPressures.count)
    }

    var body: some View {
        NavigationStack {
            List {
                if hiddenCount > 0 {
                    Section {
                        Button {
                            showingPaywall = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("\(hiddenCount) earlier readings", systemImage: "lock")
                                    .font(.subheadline.weight(.medium))
                                Text("Still saved on your device. PulseLog Plus shows your "
                                     + "full history.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !visibleBloodPressures.isEmpty {
                    Section("Blood pressure") {
                        ForEach(visibleBloodPressures) { record in
                            BloodPressureRow(reading: record.value)
                        }
                        .onDelete { delete($0, from: visibleBloodPressures) }
                    }
                }

                if !visibleHeartRates.isEmpty {
                    Section("Heart rate") {
                        ForEach(visibleHeartRates) { record in
                            HeartRateRow(reading: record.value)
                        }
                        .onDelete { delete($0, from: visibleHeartRates) }
                    }
                }

                if visibleHeartRates.isEmpty && visibleBloodPressures.isEmpty {
                    ContentUnavailableView("No readings yet",
                                           systemImage: "list.bullet",
                                           description: Text("Your measurements will appear here."))
                }
            }
            .navigationTitle("History")
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private func delete<T: PersistentModel>(_ offsets: IndexSet, from items: [T]) {
        for index in offsets { context.delete(items[index]) }
        try? context.save()
    }
}

struct HeartRateRow: View {
    let reading: HeartRateReading

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(Int(reading.bpm.rounded())) BPM")
                        .font(.body.weight(.medium)).monospacedDigit()
                    if let hrv = reading.hrvMs {
                        Text(String(format: "· HRV %.0f ms", hrv))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(reading.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                if let note = reading.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).italic()
                }
            }
            Spacer()
            Label(reading.tag.displayName, systemImage: reading.tag.symbolName)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
    }
}

struct BloodPressureRow: View {
    let reading: BloodPressureReading

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(reading.systolic)/\(reading.diastolic) mmHg")
                    .font(.body.weight(.medium)).monospacedDigit()
                Text(reading.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                if let note = reading.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).italic()
                }
            }
            Spacer()
            Text(reading.category.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.color(for: reading.category).opacity(0.15))
                .foregroundStyle(Theme.color(for: reading.category))
                .clipShape(Capsule())
        }
    }
}
